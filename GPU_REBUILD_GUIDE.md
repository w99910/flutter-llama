# GPU Acceleration Guide for Pre-Built Libraries

## 🔍 Current Status

Your pre-built `jniLibs` libraries **do NOT have Vulkan support compiled in**.

I checked your libraries and found:

- ✅ Libraries exist in: `android/app/src/main/jniLibs/`
- ❌ No Vulkan support detected
- ❌ No `libggml-vulkan.so` or Vulkan dependencies

## 🚀 Solutions (Choose One)

### Option 1: Get Pre-Built Libraries with GPU Support (Easiest)

Download pre-built llama.cpp libraries with Vulkan support:

1. **Official llama.cpp releases** (if available):

   ```bash
   # Visit: https://github.com/ggerganov/llama.cpp/releases
   # Look for Android builds with Vulkan
   ```

2. **Build using llama.cpp's Android build script**:

   ```bash
   cd android/app/src/main/cpp/llama.cpp

   # For Android x86_64 (emulator) with Vulkan
   ./build-android.sh vulkan x86_64

   # For ARM64 (physical device) with Vulkan
   ./build-android.sh vulkan arm64-v8a

   # Copy the built libraries to jniLibs
   cp build/android-x86_64-vulkan/lib/*.so ../../jniLibs/x86_64/
   cp build/android-arm64-v8a-vulkan/lib/*.so ../../jniLibs/arm64-v8a/
   ```

### Option 2: Build Libraries Yourself with Vulkan

If you want to build from source:

```bash
cd android/app/src/main/cpp/llama.cpp

# Install Android NDK if not already installed
# Set ANDROID_NDK environment variable

# Build for x86_64 (emulator) with Vulkan
mkdir -p build/android-x86_64
cd build/android-x86_64

cmake ../.. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=x86_64 \
  -DANDROID_PLATFORM=android-24 \
  -DGGML_VULKAN=ON \
  -DCMAKE_BUILD_TYPE=Release

make -j$(nproc)

# Copy libraries
cp lib/*.so ../../../jniLibs/x86_64/
```

### Option 3: Optimize for CPU Performance (Quickest)

If you can't rebuild with GPU support right now, optimize CPU performance:

#### A. Use Smaller/Faster Models

Replace your current model with a faster one:

```dart
// In lib/main.dart, change to a smaller model:

// Option 1: Tiny model for testing (270M parameters)
String _currentRepoId = "unsloth/gemma-3-270m-it-GGUF";
String _currentFileName = "gemma-3-270m-it-Q4_K_M.gguf";  // Smaller quant = faster

// Option 2: Qwen 0.6B (good balance)
String _currentRepoId = "unsloth/Qwen3-0.6B-GGUF";
String _currentFileName = "Qwen3-0.6B-Q4_K_M.gguf";
```

#### B. Reduce Context Size

In `lib/internal/llama_service.dart`, reduce context:

```dart
contextParams.n_ctx = 512;  // Instead of 2048 or 4096
```

#### C. Adjust Generation Parameters

In `lib/main.dart`, use greedy decoding for speed:

```dart
double _temperature = 0.0;  // Greedy = faster (no sampling)
int _topK = 1;
double _topP = 1.0;
```

#### D. Increase Thread Count

The libraries you have support multi-threading. The current code doesn't set thread count explicitly, but llama.cpp should auto-detect and use available cores.

## 📊 Performance Expectations

### With Current CPU-Only Libraries

| Model Size     | Emulator (x86_64) | Physical Device (ARM) |
| -------------- | ----------------- | --------------------- |
| 270M Q4        | 2-5 tokens/sec    | 5-15 tokens/sec       |
| 600M Q4        | 1-3 tokens/sec    | 3-10 tokens/sec       |
| 500M-1B Vision | 0.5-2 tokens/sec  | 2-8 tokens/sec        |

### With Vulkan GPU Support

| Model Size     | Emulator (x86_64) | Physical Device (ARM) |
| -------------- | ----------------- | --------------------- |
| 270M Q4        | 10-20 tokens/sec  | 20-40 tokens/sec      |
| 600M Q4        | 5-15 tokens/sec   | 15-30 tokens/sec      |
| 500M-1B Vision | 3-10 tokens/sec   | 10-25 tokens/sec      |

## 🔧 Verification Steps

### 1. Check if Your Libraries Have GPU Support

Run this command:

```bash
nm -D android/app/src/main/jniLibs/x86_64/libggml.so | grep vulkan
```

**If GPU support exists:** You'll see vulkan-related symbols
**If no GPU support:** Empty output (this is your current state)

### 2. Check Actual Runtime Performance

Add this to your Dart code to measure tokens/sec:

```dart
// In llama_service.dart, in the generation loop:
final startTime = DateTime.now();
int tokenCount = 0;

// ... in the token generation loop ...
tokenCount++;

// After generation completes:
final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
final tokensPerSec = tokenCount / elapsed;
print("⚡ Performance: ${tokensPerSec.toStringAsFixed(2)} tokens/sec");
```

### 3. Monitor System Resources

While running, check CPU usage:

```bash
adb shell top -n 1 | grep flutter
```

High CPU usage (>80%) = Using CPU only
Moderate CPU usage (30-60%) = Likely using GPU

## 🎯 Recommended Action Plan

**For Best Results (GPU Acceleration):**

1. ⭐ **Rebuild libraries with Vulkan** (Option 1 or 2 above)
2. Copy new libraries to `jniLibs/`
3. Run `flutter clean && flutter run`
4. Verify GPU usage with performance measurements

**For Quick Testing (CPU Optimization):**

1. Switch to smaller model (270M or 600M)
2. Reduce context size to 512
3. Use Q4_K_M quantization
4. Set temperature to 0.0 for greedy decoding

## 📝 Building Vulkan-Enabled Libraries - Step by Step

```bash
# 1. Navigate to llama.cpp directory
cd android/app/src/main/cpp/llama.cpp

# 2. Check if you have build scripts
ls -la *.sh

# 3. If you have build-android.sh:
chmod +x build-android.sh
./build-android.sh vulkan x86_64

# 4. If no build script, use manual cmake (see Option 2 above)

# 5. After build succeeds, copy libraries:
cp build/*/lib/*.so ../../jniLibs/x86_64/

# 6. Verify the new library has Vulkan:
nm -D ../../jniLibs/x86_64/libggml.so | grep vulkan

# 7. If you see vulkan symbols, you're good! Now:
flutter clean
flutter run
```

## 🆘 Troubleshooting

**Problem:** "Build script not found"

- Download fresh llama.cpp: `git clone https://github.com/ggerganov/llama.cpp`
- Or use manual CMake build (see Option 2)

**Problem:** "Vulkan headers not found during build"

- Ensure Android NDK is updated
- Install Vulkan SDK for Android
- Or use pre-built libraries instead

**Problem:** "Still slow after rebuild"

- Verify libraries have Vulkan: `nm -D libggml.so | grep vulkan`
- Check Android emulator has GPU enabled
- Try on physical device for comparison
- Measure tokens/sec to confirm

## 💡 Quick Win

For immediate speed improvement **without rebuilding**:

```dart
// In lib/main.dart - change to this tiny model:
String _currentRepoId = "unsloth/gemma-3-270m-it-GGUF";
String _currentFileName = "gemma-3-270m-it-Q4_K_M.gguf";
String? _currentMmprojFileName = null;  // No vision, just text

// This should give you 3-8 tokens/sec even on CPU!
```
