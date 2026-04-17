#!/usr/bin/env bash

set -e

# Auto-detect THEOS if not set
if [ -z "$THEOS" ]; then
    if [ -d "$HOME/theos" ]; then
        export THEOS="$HOME/theos"
    else
        echo -e '\033[1m\033[0;31mTHEOS not set and ~/theos not found.\nSet THEOS or install Theos to ~/theos\033[0m'
        exit 1
    fi
fi

CMAKE_OSX_ARCHITECTURES="arm64e;arm64"
CMAKE_OSX_SYSROOT="iphoneos"

# Copy Localization resources (*.lproj) into a RyukGram.bundle.
# Arg 1: destination bundle directory (created if missing).
copy_localization_into_bundle() {
    local DEST="$1"
    local SRC="src/Localization/Resources"
    [ -d "$SRC" ] || return 0
    mkdir -p "$DEST"
    for lproj in "$SRC"/*.lproj; do
        [ -d "$lproj" ] || continue
        cp -R "$lproj" "$DEST/"
    done
}

# Collect all FFmpegKit frameworks for injection
ffmpegkit_frameworks() {
    local fws=""
    if [ -d "modules/ffmpegkit/ffmpegkit.framework" ]; then
        for fw in modules/ffmpegkit/*.framework; do
            fws="$fws $fw"
        done
    fi
    echo "$fws"
}

# Inject RyukGram.bundle into a .deb:
# - Always: localization lproj resources.
# - Optional: FFmpegKit frameworks (renamed *_sci to avoid collisions).
# Path: Library/Application Support/RyukGram.bundle/ — jailbreak dlopens by full
# path, Feather copies .bundle without injecting load commands for sideload.
# Arg 1: path to .deb (cwd must be packages/)
inject_bundle_into_deb() {
    local BASE_DEB="$1"
    local TMPDIR=$(mktemp -d)
    dpkg-deb -R "$BASE_DEB" "$TMPDIR"
    local DYLIB_DIR=$(find "$TMPDIR" -name "RyukGram.dylib" -exec dirname {} \; | head -1)
    [ -n "$DYLIB_DIR" ] || { rm -rf "$TMPDIR"; return; }

    local PREFIX=""
    [[ "$DYLIB_DIR" == *"/var/jb/"* ]] && PREFIX="var/jb/"

    local BUNDLE_DIR="$TMPDIR/${PREFIX}Library/Application Support/RyukGram.bundle"
    mkdir -p "$BUNDLE_DIR"
    ( cd .. && copy_localization_into_bundle "$BUNDLE_DIR" )

    if [ -d "../modules/ffmpegkit/ffmpegkit.framework" ]; then
        for fw in ../modules/ffmpegkit/*.framework; do
            cp -R "$fw" "$BUNDLE_DIR/"
        done

        local LIBS="libavutil libavcodec libavformat libavfilter libavdevice libswresample libswscale"
        for lib in $LIBS; do
            mv "$BUNDLE_DIR/${lib}.framework" "$BUNDLE_DIR/${lib}_sci.framework"
            install_name_tool -id "@rpath/${lib}_sci.framework/${lib}" \
                "$BUNDLE_DIR/${lib}_sci.framework/${lib}"
        done
        for target in "$BUNDLE_DIR/ffmpegkit.framework/ffmpegkit" \
                      "$BUNDLE_DIR"/libav*_sci.framework/libav* \
                      "$BUNDLE_DIR"/libsw*_sci.framework/libsw*; do
            [ -f "$target" ] || continue
            for lib in $LIBS; do
                install_name_tool -change \
                    "@rpath/${lib}.framework/${lib}" \
                    "@rpath/${lib}_sci.framework/${lib}" \
                    "$target" 2>/dev/null || true
            done
        done
        install_name_tool -add_rpath @loader_path/.. \
            "$BUNDLE_DIR/ffmpegkit.framework/ffmpegkit" 2>/dev/null || true
    fi

    dpkg-deb -b "$TMPDIR" "$BASE_DEB"
    rm -rf "$TMPDIR"
}

# Build just the dylib (for Feather/manual injection)
if [ "$1" == "dylib" ];
then

    # --fast: incremental build (no clean)
    if [ "$2" != "--fast" ]; then
        make clean 2>/dev/null || true
        rm -rf .theos
    fi

    echo -e '\033[1m\033[32mBuilding RyukGram dylib\033[0m'

    make

    mkdir -p packages
    cp .theos/obj/debug/RyukGram.dylib packages/RyukGram.dylib

    # Ship localization bundle next to the dylib so Feather/manual installs work.
    copy_localization_into_bundle "packages/RyukGram.bundle"

    echo -e "\033[1m\033[32mDone!\033[0m\n\nDylib at: $(pwd)/packages/RyukGram.dylib\nBundle at: $(pwd)/packages/RyukGram.bundle"

# Build sideloaded IPA
elif [ "$1" == "sideload" ];
then

    # Check for FLEXing submodule
    HAS_FLEX=1
    if [ -z "$(ls -A modules/FLEXing 2>/dev/null)" ]; then
        echo -e '\033[1m\033[0;33mFLEXing submodule not found — building without FLEX debugger.\033[0m'
        echo -e '\033[0;33mTo include FLEX, run: git submodule update --init --recursive\033[0m'
        echo
        HAS_FLEX=0
    fi

    # Check if building with dev mode
    if [ "$2" == "--dev" ];
    then
        if [ "$HAS_FLEX" == "0" ]; then
            echo -e '\033[1m\033[0;31mDev mode requires FLEXing submodule.\033[0m'
            exit 1
        fi

        # Cache pre-built FLEX libs
        mkdir -p "packages/cache"
        cp -f ".theos/obj/debug/FLEXing.dylib" "packages/cache/FLEXing.dylib" 2>/dev/null || true
        cp -f ".theos/obj/debug/libflex.dylib" "packages/cache/libflex.dylib" 2>/dev/null || true

        if [[ ! -f "packages/cache/FLEXing.dylib" || ! -f "packages/cache/libflex.dylib" ]]; then
            echo -e '\033[1m\033[0;33mCould not find cached pre-built FLEX libs, building prerequisite binaries\033[0m'
            echo

            ./build.sh sideload --buildonly
            ./build-dev.sh true
            exit
        fi

        MAKEARGS='DEV=1'
        FLEXPATH='packages/cache/FLEXing.dylib packages/cache/libflex.dylib'
        COMPRESSION=0
    else
        # Clear cached FLEX libs
        rm -rf "packages/cache"

        if [ "$HAS_FLEX" == "1" ]; then
            MAKEARGS='SIDELOAD=1'
            FLEXPATH='.theos/obj/debug/FLEXing.dylib .theos/obj/debug/libflex.dylib'
        else
            MAKEARGS=''
            FLEXPATH=''
        fi
        COMPRESSION=9
    fi

    # Clean build artifacts
    make clean 2>/dev/null || true
    rm -rf .theos

    # Check for decrypted Instagram IPA
    mkdir -p packages
    ipaFile="$(find ./packages/ -maxdepth 1 -type f \( -iname '*com.burbn.instagram*.ipa' -o -iname 'Instagram*.ipa' -o -iname '[0-9]*.ipa' \) ! -iname 'RyukGram*.ipa' -exec basename {} \; 2>/dev/null | head -1)"
    if [ -z "${ipaFile}" ]; then
        # Auto-move any Instagram IPA from cwd into packages/
        cwdIpa="$(find . -maxdepth 1 -type f \( -iname '*com.burbn.instagram*.ipa' -o -iname 'Instagram*.ipa' -o -iname '[0-9]*.ipa' \) 2>/dev/null | head -1)"
        if [ -n "$cwdIpa" ]; then
            echo -e "\033[1m\033[32mMoving $(basename "$cwdIpa") → packages/\033[0m"
            mv "$cwdIpa" packages/
            ipaFile="$(basename "$cwdIpa")"
        fi
    fi
    if [ -z "${ipaFile}" ]; then
        echo -e '\033[1m\033[0;31mDecrypted Instagram IPA not found.\nPlace a *com.burbn.instagram*.ipa in ./ or ./packages/.\033[0m'
        exit 1
    fi

    # Check for cyan and ipapatch before building (skip check for --buildonly)
    if [ "$2" != "--buildonly" ]; then
        if ! command -v cyan &> /dev/null; then
            echo -e '\033[1m\033[0;31mcyan not found. Install it with:\033[0m'
            echo '  pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip'
            echo
            echo -e '\033[0;33mUse ./build.sh sideload --buildonly to just compile without creating the IPA.\033[0m'
            echo -e '\033[0;33mOr use ./build.sh dylib to build the dylib for Feather injection.\033[0m'
            exit 1
        fi
        # ipapatch disabled — upstream issues.
    fi

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for sideloading (as IPA)\033[0m'

    make $MAKEARGS

    # Copy dylib to packages
    mkdir -p packages
    cp .theos/obj/debug/RyukGram.dylib packages/RyukGram.dylib

    # Only build libs (for future use in dev build mode)
    if [ "$2" == "--buildonly" ];
    then
        exit
    fi

    # Build RyukGram.bundle with renamed frameworks for cyan injection
    BUNDLE_PATH="packages/RyukGram.bundle"
    rm -rf "$BUNDLE_PATH"
    mkdir -p "$BUNDLE_PATH"
    copy_localization_into_bundle "$BUNDLE_PATH"
    if [ -d "modules/ffmpegkit/ffmpegkit.framework" ]; then
        echo -e '\033[1m\033[32mBuilding RyukGram.bundle\033[0m'
        for fw in modules/ffmpegkit/*.framework; do
            cp -R "$fw" "$BUNDLE_PATH/"
        done
        LIBS="libavutil libavcodec libavformat libavfilter libavdevice libswresample libswscale"
        for lib in $LIBS; do
            mv "$BUNDLE_PATH/${lib}.framework" "$BUNDLE_PATH/${lib}_sci.framework"
            install_name_tool -id "@rpath/${lib}_sci.framework/${lib}" \
                "$BUNDLE_PATH/${lib}_sci.framework/${lib}"
        done
        for target in "$BUNDLE_PATH/ffmpegkit.framework/ffmpegkit" \
                      "$BUNDLE_PATH"/libav*_sci.framework/libav* \
                      "$BUNDLE_PATH"/libsw*_sci.framework/libsw*; do
            [ -f "$target" ] || continue
            for lib in $LIBS; do
                install_name_tool -change \
                    "@rpath/${lib}.framework/${lib}" \
                    "@rpath/${lib}_sci.framework/${lib}" \
                    "$target" 2>/dev/null || true
            done
        done
        install_name_tool -add_rpath @loader_path/.. \
            "$BUNDLE_PATH/ffmpegkit.framework/ffmpegkit" 2>/dev/null || true
    fi

    TWEAKPATH=".theos/obj/debug/RyukGram.dylib"
    if [ "$2" == "--devquick" ]; then TWEAKPATH=""; fi

    BUNDLE_ARG=""
    [ -d "$BUNDLE_PATH" ] && BUNDLE_ARG="$BUNDLE_PATH"

    # Create IPA: cyan injects dylib + copies RyukGram.bundle to app root
    echo -e '\033[1m\033[32mCreating the IPA file...\033[0m'
    rm -f packages/RyukGram-sideloaded.ipa
    cyan -i "packages/${ipaFile}" -o packages/RyukGram-sideloaded.ipa -f $TWEAKPATH $FLEXPATH $BUNDLE_ARG -c $COMPRESSION -m 15.0 -du

    # Inject Safari "Open in Instagram" extension into Payload/*.app/PlugIns/
    # before ipapatch re-signs, so instagram.com links open the app.
    APPEX_SRC="extensions/OpenInstagramSafariExtension.appex"
    if [ -d "$APPEX_SRC" ]; then
        echo -e '\033[1m\033[32mEmbedding Safari extension\033[0m'
        INJECT_TMP=$(mktemp -d)
        unzip -q packages/RyukGram-sideloaded.ipa -d "$INJECT_TMP"
        APP_DIR="$(find "$INJECT_TMP/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"
        if [ -n "$APP_DIR" ]; then
            mkdir -p "$APP_DIR/PlugIns"
            rm -rf "$APP_DIR/PlugIns/OpenInstagramSafariExtension.appex"
            cp -R "$APPEX_SRC" "$APP_DIR/PlugIns/"
            ( cd "$INJECT_TMP" && zip -qr -${COMPRESSION} ../repacked.ipa Payload )
            mv "$INJECT_TMP/../repacked.ipa" packages/RyukGram-sideloaded.ipa
        fi
        rm -rf "$INJECT_TMP"
    fi

    # ipapatch disabled — upstream issues.

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the ipa file at: $(pwd)/packages"

# Build rootless .deb with FFmpegKit
elif [ "$1" == "rootless" ];
then

    make clean 2>/dev/null || true
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for rootless\033[0m'

    export THEOS_PACKAGE_SCHEME=rootless
    make package

    echo -e '\033[1m\033[32mInjecting RyukGram.bundle (localization + FFmpegKit) into deb\033[0m'
    cd packages
    BASE_DEB="$(ls -t *.deb | head -n1)"
    if [ -n "$BASE_DEB" ]; then
        inject_bundle_into_deb "$BASE_DEB"
        NEW_NAME="${BASE_DEB%.deb}-rootless.deb"
        mv "$BASE_DEB" "$NEW_NAME"
    fi
    cd ..
    [ -d "modules/ffmpegkit/ffmpegkit.framework" ] || echo -e '\033[0;33mFFmpegKit not found — deb built without FFmpegKit.\033[0m'

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the deb file at: $(pwd)/packages"

# Build rootful .deb with FFmpegKit
elif [ "$1" == "rootful" ];
then

    make clean 2>/dev/null || true
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for rootful\033[0m'

    unset THEOS_PACKAGE_SCHEME
    make package

    echo -e '\033[1m\033[32mInjecting RyukGram.bundle (localization + FFmpegKit) into deb\033[0m'
    cd packages
    BASE_DEB="$(ls -t *.deb | head -n1)"
    if [ -n "$BASE_DEB" ]; then
        inject_bundle_into_deb "$BASE_DEB"
        NEW_NAME="${BASE_DEB%.deb}-rootful.deb"
        mv "$BASE_DEB" "$NEW_NAME"
    fi
    cd ..
    [ -d "modules/ffmpegkit/ffmpegkit.framework" ] || echo -e '\033[0;33mFFmpegKit not found — deb built without FFmpegKit.\033[0m'

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the deb file at: $(pwd)/packages"

# TrollStore build — .tipa is a renamed .ipa. Skip sideload re-sign; TS signs on-device.
elif [ "$1" == "trollstore" ];
then

    HAS_FLEX=1
    if [ -z "$(ls -A modules/FLEXing 2>/dev/null)" ]; then
        HAS_FLEX=0
    fi

    if [ "$HAS_FLEX" == "1" ]; then
        MAKEARGS='SIDELOAD=1'
        FLEXPATH='.theos/obj/debug/FLEXing.dylib .theos/obj/debug/libflex.dylib'
    else
        MAKEARGS=''
        FLEXPATH=''
    fi
    COMPRESSION=9

    make clean 2>/dev/null || true
    rm -rf .theos

    mkdir -p packages
    ipaFile="$(find ./packages/ -maxdepth 1 -type f \( -iname '*com.burbn.instagram*.ipa' -o -iname 'Instagram*.ipa' -o -iname '[0-9]*.ipa' \) ! -iname 'RyukGram*.ipa' -exec basename {} \; 2>/dev/null | head -1)"
    if [ -z "${ipaFile}" ]; then
        cwdIpa="$(find . -maxdepth 1 -type f \( -iname '*com.burbn.instagram*.ipa' -o -iname 'Instagram*.ipa' -o -iname '[0-9]*.ipa' \) 2>/dev/null | head -1)"
        if [ -n "$cwdIpa" ]; then
            mv "$cwdIpa" packages/
            ipaFile="$(basename "$cwdIpa")"
        fi
    fi
    if [ -z "${ipaFile}" ]; then
        echo -e '\033[1m\033[0;31mDecrypted Instagram IPA not found.\033[0m'
        exit 1
    fi

    if ! command -v cyan &> /dev/null; then
        echo -e '\033[1m\033[0;31mcyan not found. Install it with:\033[0m'
        echo '  pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip'
        exit 1
    fi

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for TrollStore (.tipa)\033[0m'
    make $MAKEARGS
    cp .theos/obj/debug/RyukGram.dylib packages/RyukGram.dylib

    BUNDLE_PATH="packages/RyukGram.bundle"
    rm -rf "$BUNDLE_PATH"
    mkdir -p "$BUNDLE_PATH"
    copy_localization_into_bundle "$BUNDLE_PATH"
    if [ -d "modules/ffmpegkit/ffmpegkit.framework" ]; then
        for fw in modules/ffmpegkit/*.framework; do
            cp -R "$fw" "$BUNDLE_PATH/"
        done
        LIBS="libavutil libavcodec libavformat libavfilter libavdevice libswresample libswscale"
        for lib in $LIBS; do
            mv "$BUNDLE_PATH/${lib}.framework" "$BUNDLE_PATH/${lib}_sci.framework"
            install_name_tool -id "@rpath/${lib}_sci.framework/${lib}" \
                "$BUNDLE_PATH/${lib}_sci.framework/${lib}"
        done
        for target in "$BUNDLE_PATH/ffmpegkit.framework/ffmpegkit" \
                      "$BUNDLE_PATH"/libav*_sci.framework/libav* \
                      "$BUNDLE_PATH"/libsw*_sci.framework/libsw*; do
            [ -f "$target" ] || continue
            for lib in $LIBS; do
                install_name_tool -change \
                    "@rpath/${lib}.framework/${lib}" \
                    "@rpath/${lib}_sci.framework/${lib}" \
                    "$target" 2>/dev/null || true
            done
        done
        install_name_tool -add_rpath @loader_path/.. \
            "$BUNDLE_PATH/ffmpegkit.framework/ffmpegkit" 2>/dev/null || true
    fi

    TWEAKPATH=".theos/obj/debug/RyukGram.dylib"
    BUNDLE_ARG=""
    [ -d "$BUNDLE_PATH" ] && BUNDLE_ARG="$BUNDLE_PATH"

    echo -e '\033[1m\033[32mCreating the TIPA file...\033[0m'
    rm -f packages/RyukGram-trollstore.tipa packages/RyukGram-trollstore.ipa
    cyan -i "packages/${ipaFile}" -o packages/RyukGram-trollstore.ipa -f $TWEAKPATH $FLEXPATH $BUNDLE_ARG -c $COMPRESSION -m 15.0 -du

    # Embed Safari extension.
    APPEX_SRC="extensions/OpenInstagramSafariExtension.appex"
    if [ -d "$APPEX_SRC" ]; then
        echo -e '\033[1m\033[32mEmbedding Safari extension\033[0m'
        INJECT_TMP=$(mktemp -d)
        unzip -q packages/RyukGram-trollstore.ipa -d "$INJECT_TMP"
        APP_DIR="$(find "$INJECT_TMP/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"
        if [ -n "$APP_DIR" ]; then
            mkdir -p "$APP_DIR/PlugIns"
            rm -rf "$APP_DIR/PlugIns/OpenInstagramSafariExtension.appex"
            cp -R "$APPEX_SRC" "$APP_DIR/PlugIns/"
            ( cd "$INJECT_TMP" && zip -qr -${COMPRESSION} ../repacked.ipa Payload )
            mv "$INJECT_TMP/../repacked.ipa" packages/RyukGram-trollstore.ipa
        fi
        rm -rf "$INJECT_TMP"
    fi

    mv packages/RyukGram-trollstore.ipa packages/RyukGram-trollstore.tipa
    echo -e "\033[1m\033[32mDone!\033[0m\n\nTIPA at: $(pwd)/packages/RyukGram-trollstore.tipa"

else
    echo '+----------------------+'
    echo '|RyukGram Build Script |'
    echo '+----------------------+'
    echo
    echo 'Usage: ./build.sh <dylib/sideload/trollstore/rootless/rootful>'
    echo
    echo '  dylib       - Build the dylib only (for Feather/manual injection)'
    echo '  sideload    - Build a patched IPA (requires cyan + decrypted IPA)'
    echo '  trollstore  - Build a .tipa for TrollStore (requires cyan + decrypted IPA)'
    echo '  rootless    - Build a rootless .deb package (with FFmpegKit)'
    echo '  rootful     - Build a rootful .deb package (with FFmpegKit)'
    exit 1
fi
