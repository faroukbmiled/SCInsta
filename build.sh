#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# RyukGram Build Script
# ============================================================

GREEN='\033[1m\033[32m'
YELLOW='\033[0;33m'
RED='\033[1m\033[0;31m'
RESET='\033[0m'

APP_NAME="RyukGram"
PACKAGES_DIR="packages"
TWEAK_DYLIB=".theos/obj/${APP_NAME}.dylib"
BUNDLE_NAME="${APP_NAME}.bundle"
BUNDLE_PATH="${PACKAGES_DIR}/${BUNDLE_NAME}"

CMAKE_OSX_ARCHITECTURES="arm64e;arm64"
CMAKE_OSX_SYSROOT="iphoneos"

log() {
	echo -e "${GREEN}$*${RESET}"
}

warn() {
	echo -e "${YELLOW}$*${RESET}"
}

die() {
	echo -e "${RED}$*${RESET}" >&2
	exit 1
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "$2"
}

# Auto-detect THEOS if not set
ensure_theos() {
	if [ -n "${THEOS:-}" ]; then
		return
	fi

	if [ -d "$HOME/theos" ]; then
		export THEOS="$HOME/theos"
	else
		die "THEOS not set and ~/theos not found.
Set THEOS or install Theos to ~/theos"
	fi
}

clean_build() {
	make clean 2>/dev/null || true
	rm -rf .theos
}

make_final() {
	make FINALPACKAGE=1 "$@"
}

ensure_packages_dir() {
	mkdir -p "$PACKAGES_DIR"
}

# Copy Localization resources (*.lproj) into a RyukGram.bundle.
# Arg 1: destination bundle directory (created if missing).
copy_localization_into_bundle() {
	local dest="$1"
	local src="src/Localization/Resources"

	[ -d "$src" ] || return 0

	mkdir -p "$dest"

	for lproj in "$src"/*.lproj; do
		[ -d "$lproj" ] || continue
		cp -R "$lproj" "$dest/"
	done
}

# Copy generic static assets (PNGs, etc.) into a RyukGram.bundle. Used for
# bundled images the tweak loads via SCILocalizationBundle().
# Arg 1: destination bundle directory (created if missing).
copy_bundle_assets() {
	local dest="$1"
	local src="src/BundleAssets"

	[ -d "$src" ] || return 0

	mkdir -p "$dest"

	find "$src" -maxdepth 1 -type f \( \
		-iname '*.png' -o \
		-iname '*.jpg' -o \
		-iname '*.jpeg' -o \
		-iname '*.pdf' \
	\) -exec cp {} "$dest/" \;
}

# Collect all FFmpegKit frameworks for injection.
# This is kept mostly as a helper/reference, but bundle building now uses
# patch_ffmpegkit_frameworks directly to avoid duplicated logic.
ffmpegkit_frameworks() {
	local fws=""

	if [ -d "modules/ffmpegkit/ffmpegkit.framework" ]; then
		for fw in modules/ffmpegkit/*.framework; do
			[ -d "$fw" ] || continue
			fws="$fws $fw"
		done
	fi

	echo "$fws"
}

# Copy FFmpegKit frameworks into RyukGram.bundle and rename FFmpeg libraries
# to *_sci to avoid collisions with frameworks that may already exist inside
# the target app.
# Arg 1: bundle path.
patch_ffmpegkit_frameworks() {
	local bundle="$1"

	[ -d "modules/ffmpegkit/ffmpegkit.framework" ] || return 0

	log "Copying FFmpegKit frameworks"

	for fw in modules/ffmpegkit/*.framework; do
		[ -d "$fw" ] || continue
		cp -R "$fw" "$bundle/"
	done

	local libs="libavutil libavcodec libavformat libavfilter libavdevice libswresample libswscale"

	for lib in $libs; do
		[ -d "$bundle/${lib}.framework" ] || continue

		mv "$bundle/${lib}.framework" "$bundle/${lib}_sci.framework"

		install_name_tool -id "@rpath/${lib}_sci.framework/${lib}" \
			"$bundle/${lib}_sci.framework/${lib}" 2>/dev/null || true
	done

	for target in "$bundle/ffmpegkit.framework/ffmpegkit" \
	              "$bundle"/libav*_sci.framework/libav* \
	              "$bundle"/libsw*_sci.framework/libsw*; do
		[ -f "$target" ] || continue

		for lib in $libs; do
			install_name_tool -change \
				"@rpath/${lib}.framework/${lib}" \
				"@rpath/${lib}_sci.framework/${lib}" \
				"$target" 2>/dev/null || true
		done
	done

	install_name_tool -add_rpath @loader_path/.. \
		"$bundle/ffmpegkit.framework/ffmpegkit" 2>/dev/null || true
}

# Build RyukGram.bundle with:
# - Localization resources
# - Static bundle assets
# - Optional FFmpegKit frameworks
# Arg 1: destination bundle path.
build_bundle() {
	local bundle="$1"

	rm -rf "$bundle"
	mkdir -p "$bundle"

	copy_localization_into_bundle "$bundle"
	copy_bundle_assets "$bundle"
	patch_ffmpegkit_frameworks "$bundle"
}

# Inject RyukGram.bundle into a .deb:
# - Always: localization lproj resources.
# - Optional: FFmpegKit frameworks renamed *_sci to avoid collisions.
# Path: Library/Application Support/RyukGram.bundle/ — jailbreak dlopens by full
# path, Feather copies .bundle without injecting load commands for sideload.
# Arg 1: path to .deb, cwd must be packages/.
inject_bundle_into_deb() {
	local base_deb="$1"
	local tmpdir

	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' RETURN

	dpkg-deb -R "$base_deb" "$tmpdir"

	local dylib_dir
	dylib_dir="$(find "$tmpdir" -name "${APP_NAME}.dylib" -exec dirname {} \; | head -1)"

	[ -n "$dylib_dir" ] || {
		rm -rf "$tmpdir"
		trap - RETURN
		return 0
	}

	local prefix=""
	[[ "$dylib_dir" == *"/var/jb/"* ]] && prefix="var/jb/"

	local bundle_dir="$tmpdir/${prefix}Library/Application Support/${BUNDLE_NAME}"

	mkdir -p "$bundle_dir"

	(
		cd ..
		copy_localization_into_bundle "$bundle_dir"
		copy_bundle_assets "$bundle_dir"
		patch_ffmpegkit_frameworks "$bundle_dir"
	)

	dpkg-deb -b "$tmpdir" "$base_deb"

	rm -rf "$tmpdir"
	trap - RETURN
}

# Build zxPluginsInject.dylib -> packages/zxPluginsInject.dylib
build_zxpi_dylib() {
	local mod_dir="modules/zxPluginsInject"
	local dylib_out="${mod_dir}/.theos/obj/zxPluginsInject.dylib"

	ensure_theos

	log "Building zxPluginsInject.dylib"

	(
		cd "$mod_dir"
		make FINALPACKAGE=1 >/dev/null
	)

	[ -f "$dylib_out" ] || die "zxPluginsInject.dylib build failed"

	ensure_packages_dir
	cp "$dylib_out" "${PACKAGES_DIR}/zxPluginsInject.dylib"

	# Match the @rpath LC that ipapatch writes into target binaries.
	install_name_tool -id "@rpath/zxPluginsInject.dylib" \
		"${PACKAGES_DIR}/zxPluginsInject.dylib" 2>/dev/null || true
}

# LC-inject zxPluginsInject.dylib into main exec + every .appex in the IPA.
# Arg 1: path to the IPA
run_ipapatch() {
	local ipa="$1"

	need_cmd ipapatch "ipapatch not found. Install it from:
  https://github.com/asdfzxcvbn/ipapatch/releases/latest"

	log "Running ipapatch (zxPluginsInject LC injection)"

	ipapatch --input "$ipa" --inplace --noconfirm --dylib "${PACKAGES_DIR}/zxPluginsInject.dylib"
}

# Find decrypted Instagram IPA.
# Checks packages/ first, then moves a matching IPA from cwd into packages/.
find_instagram_ipa() {
	ensure_packages_dir

	local ipa_file=""

	ipa_file="$(find "./${PACKAGES_DIR}" -maxdepth 1 -type f \( \
		-iname '*com.burbn.instagram*.ipa' -o \
		-iname 'Instagram*.ipa' -o \
		-iname '[0-9]*.ipa' \
	\) ! -iname "${APP_NAME}*.ipa" -exec basename {} \; 2>/dev/null | head -1)"

	if [ -n "$ipa_file" ]; then
		echo "$ipa_file"
		return 0
	fi

	local cwd_ipa=""

	cwd_ipa="$(find . -maxdepth 1 -type f \( \
		-iname '*com.burbn.instagram*.ipa' -o \
		-iname 'Instagram*.ipa' -o \
		-iname '[0-9]*.ipa' \
	\) 2>/dev/null | head -1)"

	if [ -n "$cwd_ipa" ]; then
		log "Moving $(basename "$cwd_ipa") → ${PACKAGES_DIR}/"
		mv "$cwd_ipa" "$PACKAGES_DIR/"
		echo "$(basename "$cwd_ipa")"
		return 0
	fi

	return 1
}

# Check for FLEXing submodule.
check_flex() {
	if [ -n "$(ls -A modules/FLEXing 2>/dev/null || true)" ]; then
		echo "1"
	else
		echo "0"
	fi
}

# Embed Safari extension before ipapatch resign.
# Free signing rewrites the parent bundle ID and breaks the appex prefix, so
# this is skipped for SideStore.
embed_safari_extension() {
	local ipa="$1"
	local compression="$2"
	local appex_src="extensions/OpenInstagramSafariExtension.appex"

	[ -d "$appex_src" ] || return 0

	log "Embedding Safari extension"

	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' RETURN

	unzip -q "$ipa" -d "$tmpdir"

	local app_dir
	app_dir="$(find "$tmpdir/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"

	if [ -n "$app_dir" ]; then
		mkdir -p "$app_dir/PlugIns"
		rm -rf "$app_dir/PlugIns/OpenInstagramSafariExtension.appex"
		cp -R "$appex_src" "$app_dir/PlugIns/"

		(
			cd "$tmpdir"
			zip -qr -"${compression}" ../repacked.ipa Payload
		)

		mv "$tmpdir/../repacked.ipa" "$ipa"
	fi

	rm -rf "$tmpdir"
	trap - RETURN
}

# Strip every .appex.
# Instagram keeps some under Extensions/, not only PlugIns/.
# Free signing's bundle ID rewrite breaks the parent-prefix check otherwise.
strip_appex_bundles() {
	local ipa="$1"
	local compression="$2"

	log "Stripping app extensions for SideStore"

	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' RETURN

	unzip -q "$ipa" -d "$tmpdir"

	local app_dir
	app_dir="$(find "$tmpdir/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"

	if [ -n "$app_dir" ]; then
		local appex_count
		appex_count="$(find "$app_dir" -type d -name '*.appex' | wc -l | tr -d ' ')"

		find "$app_dir" -type d -name '*.appex' -prune -exec rm -rf {} +

		warn "  removed ${appex_count} .appex bundle(s)"

		(
			cd "$tmpdir"
			zip -qr -"${compression}" ../repacked.ipa Payload
		)

		mv "$tmpdir/../repacked.ipa" "$ipa"
	fi

	rm -rf "$tmpdir"
	trap - RETURN
}

# Build just the dylib for Feather/manual injection.
build_dylib() {
	local option="${1:-}"

	# --fast: incremental build, no clean.
	if [ "$option" != "--fast" ]; then
		clean_build
	fi

	log "Building ${APP_NAME} dylib"

	make_final

	ensure_packages_dir
	cp "$TWEAK_DYLIB" "${PACKAGES_DIR}/${APP_NAME}.dylib"

	# Ship localization bundle next to the dylib so Feather/manual installs work.
	rm -rf "$BUNDLE_PATH"
	mkdir -p "$BUNDLE_PATH"
	copy_localization_into_bundle "$BUNDLE_PATH"
	copy_bundle_assets "$BUNDLE_PATH"

	log "Done!"
	echo
	echo "Dylib at:  $(pwd)/${PACKAGES_DIR}/${APP_NAME}.dylib"
	echo "Bundle at: $(pwd)/${BUNDLE_PATH}"
}

# Build sideloaded IPA.
# sidestore = sideload + in-tweak SideloadPatch, no zxPluginsInject/ipapatch.
build_sideload() {
	local mode="${1:-sideload}"
	local option="${2:-}"

	local rg_sidestore=0
	local build_label="sideloading"
	local out_ipa="${PACKAGES_DIR}/${APP_NAME}-sideloaded.ipa"
	local compression=9
	local makeargs=()
	local flexpath=()

	if [ "$mode" = "sidestore" ]; then
		rg_sidestore=1
		export RG_SIDESTORE=1
		build_label="SideStore"
		out_ipa="${PACKAGES_DIR}/${APP_NAME}-sidestore.ipa"
	fi

	# Check for FLEXing submodule.
	local has_flex
	has_flex="$(check_flex)"

	if [ "$has_flex" = "0" ]; then
		warn "FLEXing submodule not found — building without FLEX debugger."
		warn "To include FLEX, run: git submodule update --init --recursive"
		echo
	fi

	# Check if building with dev mode.
	if [ "$option" = "--dev" ]; then
		[ "$has_flex" = "1" ] || die "Dev mode requires FLEXing submodule."

		# Cache pre-built FLEX libs.
		ensure_packages_dir
		mkdir -p "${PACKAGES_DIR}/cache"

		cp -f ".theos/obj/FLEXing.dylib" "${PACKAGES_DIR}/cache/FLEXing.dylib" 2>/dev/null || true
		cp -f ".theos/obj/libflex.dylib" "${PACKAGES_DIR}/cache/libflex.dylib" 2>/dev/null || true

		if [[ ! -f "${PACKAGES_DIR}/cache/FLEXing.dylib" || ! -f "${PACKAGES_DIR}/cache/libflex.dylib" ]]; then
			warn "Could not find cached pre-built FLEX libs, building prerequisite binaries"
			echo

			"$0" sideload --buildonly
			./build-dev.sh true
			exit 0
		fi

		makeargs+=(DEV=1)
		flexpath+=("${PACKAGES_DIR}/cache/FLEXing.dylib" "${PACKAGES_DIR}/cache/libflex.dylib")
		compression=0
	else
		# Clear cached FLEX libs.
		rm -rf "${PACKAGES_DIR}/cache"

		if [ "$has_flex" = "1" ]; then
			makeargs+=(SIDELOAD=1)
			flexpath+=(".theos/obj/FLEXing.dylib" ".theos/obj/libflex.dylib")
		fi

		compression=9
	fi

	if [ "$rg_sidestore" = "1" ]; then
		makeargs+=(SIDESTORE=1)
	fi

	# Clean build artifacts.
	clean_build
	ensure_packages_dir

	# Check for decrypted Instagram IPA.
	local ipa_file
	ipa_file="$(find_instagram_ipa)" || die "Decrypted Instagram IPA not found.
Place a *com.burbn.instagram*.ipa in ./ or ./packages/."

	# Check for cyan and ipapatch before building.
	# Skip full IPA tool checks for --buildonly.
	if [ "$option" != "--buildonly" ]; then
		need_cmd cyan "cyan not found. Install it with:
  pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip

Use ./build.sh sideload --buildonly to just compile without creating the IPA.
Or use ./build.sh dylib to build the dylib for Feather injection."

		if [ "$rg_sidestore" != "1" ]; then
			need_cmd ipapatch "ipapatch not found. Install it from:
  https://github.com/asdfzxcvbn/ipapatch/releases/latest"
		fi
	fi

	log "Building ${APP_NAME} tweak for ${build_label} as IPA"

	make_final "${makeargs[@]}"

	# Skip zxPluginsInject for SideStore — its LC injection trips ldid on resign.
	if [ "$rg_sidestore" != "1" ]; then
		build_zxpi_dylib
	fi

	# Copy dylib to packages.
	cp "$TWEAK_DYLIB" "${PACKAGES_DIR}/${APP_NAME}.dylib"

	# Only build libs for future use in dev build mode.
	if [ "$option" = "--buildonly" ]; then
		log "Build-only finished."
		exit 0
	fi

	# Build RyukGram.bundle with renamed frameworks for cyan injection.
	log "Building ${BUNDLE_NAME}"
	build_bundle "$BUNDLE_PATH"

	local tweakpath="$TWEAK_DYLIB"

	if [ "$option" = "--devquick" ]; then
		tweakpath=""
	fi

	local cyan_files=()

	if [ -n "$tweakpath" ]; then
		cyan_files+=("$tweakpath")
	fi

	if [ "${#flexpath[@]}" -gt 0 ]; then
		cyan_files+=("${flexpath[@]}")
	fi

	if [ -d "$BUNDLE_PATH" ]; then
		cyan_files+=("$BUNDLE_PATH")
	fi

	# Create IPA: cyan injects dylib + copies RyukGram.bundle to app root.
	log "Creating the IPA file"

	rm -f "$out_ipa"

	cyan -i "${PACKAGES_DIR}/${ipa_file}" \
		-o "$out_ipa" \
		-f "${cyan_files[@]}" \
		-c "$compression" \
		-m 15.0 \
		-du

	# Embed Safari extension before ipapatch resign.
	# Skip on SideStore because free signing rewrites the parent bundle ID
	# and breaks the appex prefix.
	if [ "$rg_sidestore" != "1" ]; then
		embed_safari_extension "$out_ipa" "$compression"
	else
		strip_appex_bundles "$out_ipa" "$compression"
	fi

	if [ "$rg_sidestore" != "1" ]; then
		run_ipapatch "$out_ipa"
	fi

	log "Done, enjoy ${APP_NAME}!"
	echo
	echo "IPA at: $(pwd)/$out_ipa"
}

# Build rootless/rootful .deb with FFmpegKit.
build_deb() {
	local scheme="$1"

	clean_build
	ensure_packages_dir

	if [ "$scheme" = "rootless" ]; then
		log "Building ${APP_NAME} tweak for rootless"
		export THEOS_PACKAGE_SCHEME=rootless
	else
		log "Building ${APP_NAME} tweak for rootful"
		unset THEOS_PACKAGE_SCHEME
	fi

	make_final package

	log "Injecting ${BUNDLE_NAME} with localization + FFmpegKit into deb"

	(
		cd "$PACKAGES_DIR"

		local base_deb
		base_deb="$(ls -t *.deb 2>/dev/null | head -n1)"

		[ -n "$base_deb" ] || die "No deb package found."

		inject_bundle_into_deb "$base_deb"

		local new_name="${base_deb%.deb}-${scheme}.deb"
		mv "$base_deb" "$new_name"
	)

	[ -d "modules/ffmpegkit/ffmpegkit.framework" ] || warn "FFmpegKit not found — deb built without FFmpegKit."

	log "Done, enjoy ${APP_NAME}!"
	echo
	echo "Deb at: $(pwd)/${PACKAGES_DIR}"
}

# TrollStore build — .tipa is a renamed .ipa.
# Skip sideload re-sign; TrollStore signs on-device.
build_trollstore() {
	local has_flex
	has_flex="$(check_flex)"

	local makeargs=()
	local flexpath=()
	local compression=9

	if [ "$has_flex" = "1" ]; then
		makeargs+=(SIDELOAD=1)
		flexpath+=(".theos/obj/FLEXing.dylib" ".theos/obj/libflex.dylib")
	fi

	clean_build
	ensure_packages_dir

	local ipa_file
	ipa_file="$(find_instagram_ipa)" || die "Decrypted Instagram IPA not found."

	need_cmd cyan "cyan not found. Install it with:
  pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip"

	need_cmd ipapatch "ipapatch not found. Install it from:
  https://github.com/asdfzxcvbn/ipapatch/releases/latest"

	log "Building ${APP_NAME} tweak for TrollStore .tipa"

	make_final "${makeargs[@]}"

	cp "$TWEAK_DYLIB" "${PACKAGES_DIR}/${APP_NAME}.dylib"

	build_zxpi_dylib

	# Build RyukGram.bundle with renamed frameworks for cyan injection.
	log "Building ${BUNDLE_NAME}"
	build_bundle "$BUNDLE_PATH"

	local out_ipa="${PACKAGES_DIR}/${APP_NAME}-trollstore.ipa"
	local out_tipa="${PACKAGES_DIR}/${APP_NAME}-trollstore.tipa"

	local cyan_files=("$TWEAK_DYLIB")

	if [ "${#flexpath[@]}" -gt 0 ]; then
		cyan_files+=("${flexpath[@]}")
	fi

	if [ -d "$BUNDLE_PATH" ]; then
		cyan_files+=("$BUNDLE_PATH")
	fi

	log "Creating the TIPA file"

	rm -f "$out_ipa" "$out_tipa"

	cyan -i "${PACKAGES_DIR}/${ipa_file}" \
		-o "$out_ipa" \
		-f "${cyan_files[@]}" \
		-c "$compression" \
		-m 15.0 \
		-du

	# Embed Safari extension.
	embed_safari_extension "$out_ipa" "$compression"

	run_ipapatch "$out_ipa"

	mv "$out_ipa" "$out_tipa"

	log "Done!"
	echo
	echo "TIPA at: $(pwd)/$out_tipa"
}

usage() {
	echo '+-----------------------+'
	echo '| RyukGram Build Script |'
	echo '+-----------------------+'
	echo
	echo "Usage: $0 <dylib/sideload/sidestore/trollstore/rootless/rootful> [option]"
	echo
	echo 'Commands:'
	echo '  dylib                 Build the dylib only for Feather/manual injection'
	echo '  dylib --fast          Build dylib without cleaning'
	echo '  sideload              Build a patched IPA, requires cyan + decrypted IPA'
	echo '  sideload --buildonly  Compile only, do not create IPA'
	echo '  sideload --dev        Build dev IPA with cached FLEX libs'
	echo '  sideload --devquick   Create IPA without RyukGram.dylib injection'
	echo '  sidestore             Like sideload, plus legacy sideload compatibility patch'
	echo '                        keychain/app group/CloudKit fixes for SideStore installs'
	echo '  trollstore            Build a .tipa for TrollStore, requires cyan + decrypted IPA'
	echo '  rootless              Build a rootless .deb package with FFmpegKit'
	echo '  rootful               Build a rootful .deb package with FFmpegKit'
	echo
	exit 1
}

main() {
	ensure_theos

	local command="${1:-}"
	local option="${2:-}"

	case "$command" in
		dylib)
			build_dylib "$option"
			;;
		sideload)
			build_sideload "sideload" "$option"
			;;
		sidestore)
			build_sideload "sidestore" "$option"
			;;
		trollstore)
			build_trollstore
			;;
		rootless)
			build_deb "rootless"
			;;
		rootful)
			build_deb "rootful"
			;;
		*)
			usage
			;;
	esac
}

main "$@"