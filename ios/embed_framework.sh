#!/bin/bash

# This script embeds the llama.xcframework into the iOS app bundle
# Run this as a build phase in Xcode or manually before building

FRAMEWORK_PATH="${SRCROOT}/Frameworks/llama.xcframework"
APP_FRAMEWORKS="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [ -d "$FRAMEWORK_PATH" ]; then
    echo "Embedding llama.xcframework..."
    
    # Create Frameworks directory if it doesn't exist
    mkdir -p "$APP_FRAMEWORKS"
    
    # Copy the appropriate slice of the xcframework
    if [ "$PLATFORM_NAME" = "iphoneos" ]; then
        # Device build
        cp -R "${FRAMEWORK_PATH}/ios-arm64/llama.framework" "$APP_FRAMEWORKS/"
    else
        # Simulator build
        cp -R "${FRAMEWORK_PATH}/ios-arm64_x86_64-simulator/llama.framework" "$APP_FRAMEWORKS/"
    fi
    
    echo "llama.framework embedded successfully"
else
    echo "Error: llama.xcframework not found at $FRAMEWORK_PATH"
    exit 1
fi
