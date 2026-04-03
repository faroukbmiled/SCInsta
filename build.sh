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

# Build just the dylib (for Feather/manual injection)
if [ "$1" == "dylib" ];
then

    make clean 2>/dev/null || true
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding RyukGram dylib\033[0m'

    make

    mkdir -p packages
    cp .theos/obj/debug/RyukGram.dylib packages/RyukGram.dylib

    echo -e "\033[1m\033[32mDone!\033[0m\n\nDylib at: $(pwd)/packages/RyukGram.dylib"

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
    ipaFile="$(find ./packages/ -name '*com.burbn.instagram*.ipa' -type f -exec basename {} \; 2>/dev/null || true)"
    if [ -z "${ipaFile}" ]; then
        echo -e '\033[1m\033[0;31m./packages/com.burbn.instagram.ipa not found.\nPlease put a decrypted Instagram IPA in its path.\033[0m'
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
        if ! command -v ipapatch &> /dev/null; then
            echo -e '\033[1m\033[0;31mipapatch not found. Install it from:\033[0m'
            echo '  https://github.com/asdfzxcvbn/ipapatch/releases/latest'
            echo
            echo -e '\033[0;33mUse ./build.sh sideload --buildonly to just compile without creating the IPA.\033[0m'
            echo -e '\033[0;33mOr use ./build.sh dylib to build the dylib for Feather injection.\033[0m'
            exit 1
        fi
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

    TWEAKPATH=".theos/obj/debug/RyukGram.dylib"
    if [ "$2" == "--devquick" ];
    then
        # Exclude RyukGram.dylib from IPA for livecontainer quick builds
        TWEAKPATH=""
    fi

    # Create IPA file
    echo -e '\033[1m\033[32mCreating the IPA file...\033[0m'
    rm -f packages/RyukGram-sideloaded.ipa
    cyan -i "packages/${ipaFile}" -o packages/RyukGram-sideloaded.ipa -f $TWEAKPATH $FLEXPATH -c $COMPRESSION -m 15.0 -du

    # Patch IPA for sideloading
    ipapatch --input "packages/RyukGram-sideloaded.ipa" --inplace --noconfirm

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the ipa file at: $(pwd)/packages"

# Build rootless .deb
elif [ "$1" == "rootless" ];
then

    make clean 2>/dev/null || true
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for rootless\033[0m'

    export THEOS_PACKAGE_SCHEME=rootless
    make package

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the deb file at: $(pwd)/packages"

# Build rootful .deb
elif [ "$1" == "rootful" ];
then

    make clean 2>/dev/null || true
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for rootful\033[0m'

    unset THEOS_PACKAGE_SCHEME
    make package

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the deb file at: $(pwd)/packages"

else
    echo '+----------------------+'
    echo '|RyukGram Build Script |'
    echo '+----------------------+'
    echo
    echo 'Usage: ./build.sh <dylib/sideload/rootless/rootful>'
    echo
    echo '  dylib     - Build the dylib only (for Feather/manual injection)'
    echo '  sideload  - Build a patched IPA (requires cyan + ipapatch + decrypted IPA)'
    echo '  rootless  - Build a rootless .deb package'
    echo '  rootful   - Build a rootful .deb package'
    exit 1
fi
