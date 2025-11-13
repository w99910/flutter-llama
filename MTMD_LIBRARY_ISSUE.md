# MTMD Library Not Available Issue

## Error
```
Invalid argument(s): Failed to lookup symbol 'mtmd_context_params_default': 
dlsym(RTLD_DEFAULT, mtmd_context_params_default): symbol not found
```

## Problem
The iOS framework (`llama.xcframework`) was built **without multimodal support**. The mtmd (multimodal) functions are not compiled into the library, so vision models cannot be loaded.

## Why This Happens
The llama.cpp library needs to be explicitly built with multimodal support enabled. By default, it only includes text-generation capabilities. To support vision models (like SmolVLM, LLaVA, etc.), the library must be compiled with the `LLAMA_MULTIMODAL=ON` flag.

## Solution: Rebuild llama.cpp with Multimodal Support

### Step 1: Get the llama.cpp Source
```bash
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
```

### Step 2: Build for iOS with Multimodal Support

Create a build script `build_ios_multimodal.sh`:

```bash
#!/bin/bash

# Clean previous builds
rm -rf build-ios
mkdir -p build-ios

# Configure with multimodal support
cmake -B build-ios \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_MULTIMODAL=ON \
  -DLLAMA_METAL=ON \
  -DGGML_METAL=ON \
  -DBUILD_SHARED_LIBS=OFF

# Build
cmake --build build-ios --config Release -j 8

# Create XCFramework
xcodebuild -create-xcframework \
  -library build-ios/libllama.a \
  -headers include \
  -output llama.xcframework
```

### Step 3: Replace the Framework

1. Copy the new `llama.xcframework` to your Flutter project:
   ```bash
   cp -r llama.xcframework /path/to/flutter-llama/ios/Frameworks/
   ```

2. Clean and rebuild your Flutter app:
   ```bash
   cd /path/to/flutter-llama
   flutter clean
   flutter pub get
   flutter run --release
   ```

## Workaround: Text-Only Mode

The app has been updated to gracefully handle missing mtmd support:

1. **Detection**: The app now checks if mtmd functions are available during initialization
2. **Fallback**: If mtmd is not available, the app continues in text-only mode
3. **Warning**: Clear messages are printed to indicate vision features are disabled

### What You'll See:
```
⚠️  Multimodal functions not available
   Vision/audio features will be disabled.
   Note: Rebuild llama.cpp with LLAMA_MULTIMODAL=ON
```

The model will still load and work for **text generation**, but:
- Cannot process images
- Cannot use vision models (SmolVLM, LLaVA, etc.)
- Works fine with text-only models (Llama, Mistral, etc.)

## Verification

After rebuilding with multimodal support, you should see:
```
✅ Multimodal library (mtmd) loaded successfully
```

And when loading a vision model:
```
Loading multimodal projector from: /path/to/mmproj-*.gguf
Multimodal projector loaded successfully!
  - Vision support: true
  - Audio support: false
```

## Build Requirements

### For iOS:
- Xcode 14+
- CMake 3.20+
- iOS SDK 13.0+

### CMake Flags for Multimodal:
- `LLAMA_MULTIMODAL=ON` - Enable multimodal support (vision/audio)
- `LLAMA_METAL=ON` - Enable Metal GPU acceleration (iOS)
- `GGML_METAL=ON` - Enable Metal for GGML operations

## Alternative: Pre-built Binaries

If you don't want to build from source, you can try:

1. **Check llama.cpp releases**: Some releases include pre-built iOS frameworks with multimodal support
2. **Use community builds**: Look for iOS builds with multimodal enabled
3. **Build server**: Set up a CI/CD pipeline to automatically build with the correct flags

## Testing After Rebuild

```dart
// Test code to verify mtmd is available
final service = LlamaService();
print('Supports vision: ${service.supportsVision}');

// Try loading a vision model
service.loadModel(
  '/path/to/SmolVLM-Instruct-Q4_K_M.gguf',
  mmprojPath: '/path/to/mmproj-SmolVLM-Instruct-f16.gguf',
);
```

If successful, you'll be able to use vision models with image input!

## References
- [llama.cpp Multimodal Documentation](https://github.com/ggerganov/llama.cpp/blob/master/examples/llava/README.md)
- [Building llama.cpp for iOS](https://github.com/ggerganov/llama.cpp/blob/master/docs/build.md)
- [Metal GPU Acceleration](https://github.com/ggerganov/llama.cpp/blob/master/docs/backend/Metal.md)
