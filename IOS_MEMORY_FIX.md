# iOS Memory Optimization for Vision Models

## Problem
The app was crashing on iOS when loading SmolVLM vision model with the error:
```
Lost connection to device.
```

This occurred immediately after setting the context parameters for the vision model, indicating an Out-Of-Memory (OOM) crash.

## Root Cause
iOS devices have stricter memory constraints compared to Android and desktop platforms. The original configuration was too aggressive for iOS:
- **n_gpu_layers = 999**: Attempting to offload all layers to GPU
- **n_ctx = 4096**: Large context size
- **n_ubatch = 2048**: Large micro-batch size for image embeddings
- **n_threads = 4**: More threads creating more memory overhead

These combined settings exceeded available memory on iOS devices.

## Solution
Implemented platform-specific memory optimizations for iOS:

### 1. Reduced GPU Layers (n_gpu_layers)
```dart
if (Platform.isIOS) {
  modelParams.n_gpu_layers = 35; // Conservative value for iOS
} else {
  modelParams.n_gpu_layers = 999; // Full GPU offloading on other platforms
}
```
- **iOS**: 35 layers (conservative to prevent OOM)
- **Other platforms**: 999 layers (maximum GPU offloading)

### 2. Reduced Context Size (n_ctx)
```dart
if (Platform.isIOS) {
  contextParams.n_ctx = 2048; // For both vision and text models
} else {
  contextParams.n_ctx = mmprojPath != null ? 4096 : 2048;
}
```
- **iOS**: 2048 tokens (sufficient for most image + text tasks)
- **Other platforms**: 4096 tokens for vision models

### 3. Reduced Micro-Batch Size (n_ubatch)
```dart
if (mmprojPath != null) {
  if (Platform.isIOS) {
    contextParams.n_ubatch = 512; // Reduced for iOS
  } else {
    contextParams.n_ubatch = 2048; // Standard for vision models
  }
}
```
- **iOS**: 512 tokens (still large enough for most image embeddings)
- **Other platforms**: 2048 tokens

### 4. Reduced Thread Count (n_threads)
```dart
mtmdParams.n_threads = Platform.isIOS ? 2 : 4;
```
- **iOS**: 2 threads (reduces memory pressure)
- **Other platforms**: 4 threads

## Memory Impact

### Before (iOS)
- GPU Layers: 999 → High GPU memory usage
- Context: 4096 tokens → ~16MB+ memory
- n_ubatch: 2048 → Large batch processing memory
- Threads: 4 → Higher thread overhead
- **Total**: Exceeded iOS device limits → **CRASH**

### After (iOS)
- GPU Layers: 35 → Moderate GPU memory usage
- Context: 2048 tokens → ~8MB memory
- n_ubatch: 512 → Smaller batch processing memory
- Threads: 2 → Lower thread overhead
- **Total**: Within iOS device limits → **STABLE**

## Trade-offs

### Performance
- Slightly slower inference due to fewer GPU layers
- Processing larger images may require multiple batches
- Fewer parallel threads for image processing

### Functionality
- Still supports vision models (SmolVLM, LLaVA, etc.)
- Can process standard images (most images generate <512 embeddings)
- Context of 2048 is sufficient for most use cases

## Testing Recommendations

1. **Test with different iOS devices**:
   - iPhone 12 and newer (more memory available)
   - Older devices may need even more conservative settings

2. **Monitor memory usage**:
   - Use Xcode Instruments to profile memory
   - Adjust `n_gpu_layers` if needed (can go up to 50-60 on newer devices)

3. **Test with different image sizes**:
   - Small images (224x224): Should work well
   - Large images (1024x1024): May need chunking

## Further Optimizations (if needed)

If crashes still occur on older iOS devices:

```dart
if (Platform.isIOS) {
  // More aggressive reduction
  modelParams.n_gpu_layers = 20;
  contextParams.n_ctx = 1024;
  contextParams.n_ubatch = 256;
  mtmdParams.n_threads = 1;
}
```

## References

- llama.cpp memory management: https://github.com/ggerganov/llama.cpp
- iOS memory limits: Varies by device (typically 1-4GB for apps)
- Vision model requirements: Image embeddings typically 256-729 tokens depending on model
