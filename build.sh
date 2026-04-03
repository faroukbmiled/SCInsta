#!/usr/bin/env bash

set -e

CMAKE_OSX_ARCHITECTURES="arm64e;arm64"
CMAKE_OSX_SYSROOT="iphoneos"

# Building modes
if [ "$1" == "sideload" ];
then

    # FLEXing is only needed for sideload builds
    if [ -z "$(ls -A modules/FLEXing 2>/dev/null)" ]; then
        echo -e '\033[1m\033[0;31mFLEXing submodule not found.\nPlease run the following command to checkout submodules:\n\n\033[0m    git submodule update --init --recursive'
        exit 1
    fi

    # Check if building with dev mode
    if [ "$2" == "--dev" ];
    then
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

        MAKEARGS='SIDELOAD=1'
        FLEXPATH='.theos/obj/debug/FLEXing.dylib .theos/obj/debug/libflex.dylib'
        COMPRESSION=9
    fi

    # Clean build artifacts
    make clean
    rm -rf .theos

    # Check for decrypted instagram ipa
    ipaFile="$(find ./packages/*com.burbn.instagram*.ipa -type f -exec basename {} \;)"
    if [ -z "${ipaFile}" ]; then
        echo -e '\033[1m\033[0;31m./packages/com.burbn.instagram.ipa not found.\nPlease put a decrypted Instagram IPA in its path.\033[0m'
        exit 1
    fi

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for sideloading (as IPA)\033[0m'

    make $MAKEARGS

    # Only build libs (for future use in dev build mode)
    if [ "$2" == "--buildonly" ];
    then
        exit
    fi

    TWEAKPATH=".theos/obj/debug/RyukGram.dylib"
    if [ "$2" == "--devquick" ];
    then
        TWEAKPATH=""
    fi

    # Create IPA File
    echo -e '\033[1m\033[32mCreating the IPA file...\033[0m'
    rm -f packages/RyukGram-sideloaded.ipa
    cyan -i "packages/${ipaFile}" -o packages/RyukGram-sideloaded.ipa -f $TWEAKPATH $FLEXPATH -c $COMPRESSION -m 15.0 -du

    # Patch IPA for sideloading
    ipapatch --input "packages/RyukGram-sideloaded.ipa" --inplace --noconfirm

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the ipa file at: $(pwd)/packages"

elif [ "$1" == "rootless" ];
then

    # Clean build artifacts
    make clean
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding RyukGram tweak for rootless\033[0m'

    export THEOS_PACKAGE_SCHEME=rootless
    make package

    echo -e "\033[1m\033[32mDone, enjoy RyukGram!\033[0m\n\nYou can find the deb file at: $(pwd)/packages"

elif [ "$1" == "rootful" ];
then

    # Clean build artifacts
    make clean
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
    echo 'Usage: ./build.sh <sideload/rootless/rootful>'
    exit 1
fi
