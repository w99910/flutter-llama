# Vision Model Support

This app now supports vision-capable LLMs that can understand and describe images!

## How It Works

Vision models in llama.cpp require two files:

1. **Main model file** (.gguf) - The language model
2. **Multimodal projector file** (mmproj-\*.gguf) - Handles image encoding

## Using Vision Models

### 1. Configure a Vision Model

In `main.dart`, update the model configuration to include an mmproj file:

```dart
// Example: SmolVLM (Small, fast vision model)
String _currentRepoId = "ggml-org/SmolVLM-Instruct-GGUF";
String _currentFileName = "SmolVLM-Instruct-Q4_K_M.gguf";
String? _currentMmprojFileName = "mmproj-SmolVLM-Instruct-Q8_0.gguf";
```

### 2. Add Images

1. Tap the image button (📷) in the input area
2. Choose between Camera or Gallery
3. Select one or more images
4. A badge will show how many images are queued
5. Type your question or leave blank for "Describe this image"
6. Tap send - images will be included with your message

### 3. Vision Model Prompts

For vision models, add `<image>` markers in your prompt. The app automatically adds these markers based on the number of images you've selected.

Example prompts:

- "What's in this image?"
- "Describe this image in detail"
- "What objects can you see?"
- "Read the text in this image"

## Recommended Vision Models

### 🌟 SmolVLM (500M - Best for mobile)

- **Repo**: `HuggingFaceTB/SmolVLM-Instruct-GGUF`
- **Model**: `smolvlm-instruct-q4_k_m.gguf`
- **Mmproj**: `mmproj-smolvlm-instruct-f16.gguf`
- **Size**: ~300MB + 150MB
- **Speed**: Very fast
- **Use case**: Great for mobile devices, good general vision understanding

### 🚀 LLaVA 1.5 (7B - Balanced)

- **Repo**: `mys/ggml_llava-v1.5-7b`
- **Model**: `llava-v1.5-7b-Q4_K_M.gguf`
- **Mmproj**: `llava-v1.5-7b-mmproj-f16.gguf`
- **Size**: ~4GB + 600MB
- **Speed**: Medium
- **Use case**: Good balance of quality and speed

### 💎 Qwen2-VL (7B - High quality)

- **Repo**: `Qwen/Qwen2-VL-7B-Instruct-GGUF`
- **Model**: `qwen2-vl-7b-instruct-q4_k_m.gguf`
- **Mmproj**: `mmproj-qwen2-vl-7b-instruct-f16.gguf`
- **Size**: ~4.5GB + 700MB
- **Speed**: Medium
- **Use case**: Better accuracy, good for detailed descriptions

### 🔥 MiniCPM-V 2.6 (8B - State-of-the-art)

- **Repo**: `openbmb/MiniCPM-V-2_6-gguf`
- **Model**: `ggml-model-Q4_K_M.gguf`
- **Mmproj**: `mmproj-model-f16.gguf`
- **Size**: ~5GB + 800MB
- **Speed**: Slower but very accurate
- **Use case**: Best quality, supports multilingual

### ⚡ Gemma 3 4B-VL (4B - Google's model)

- **Repo**: `google/gemma-3-4b-it-GGUF`
- **Model**: `gemma-3-4b-it-Q4_K_M.gguf`
- **Mmproj**: `mmproj-gemma-3-4b-it-f16.gguf`
- **Size**: ~2.5GB + 400MB
- **Speed**: Fast
- **Use case**: Good for most tasks, efficient

## Configuration Examples

### SmolVLM (Recommended for starting)

```dart
String _currentRepoId = "HuggingFaceTB/SmolVLM-Instruct-GGUF";
String _currentFileName = "smolvlm-instruct-q4_k_m.gguf";
String? _currentMmprojFileName = "mmproj-smolvlm-instruct-f16.gguf";
```

### LLaVA 1.5

```dart
String _currentRepoId = "mys/ggml_llava-v1.5-7b";
String _currentFileName = "llava-v1.5-7b-Q4_K_M.gguf";
String? _currentMmprojFileName = "llava-v1.5-7b-mmproj-f16.gguf";
```

### Qwen2-VL

```dart
String _currentRepoId = "Qwen/Qwen2-VL-7B-Instruct-GGUF";
String _currentFileName = "qwen2-vl-7b-instruct-q4_k_m.gguf";
String? _currentMmprojFileName = "mmproj-qwen2-vl-7b-instruct-f16.gguf";
```

## Tips

1. **First time**: The app will download both model and mmproj files automatically
2. **Storage**: Vision models need more space (model + mmproj)
3. **RAM**: Vision models use more memory when processing images
4. **Speed**: Smaller models (SmolVLM) are much faster than larger ones
5. **Quality**: Larger models give better, more detailed descriptions
6. **Multiple images**: You can send multiple images at once
7. **Text optional**: You can send just images without text prompts

## Troubleshooting

### Model loads but images don't work

- Make sure both model AND mmproj files are configured
- Check that the mmproj file matches your model version
- Verify that `_currentMmprojFileName` is set (not null)

### "Vision disabled" error

- The mmproj file wasn't loaded successfully
- Check file paths and ensure mmproj exists
- Try re-downloading by deleting the files

### Images show but no response

- The current implementation uses low-level FFI bindings
- For full vision support, consider using llama_cpp_dart's high-level `Llama` class with `generateWithMedia()`
- Check the console logs for integration hints

## Technical Details

The vision support is based on llama.cpp's multimodal (mtmd) implementation:

- Images are encoded using CLIP-based vision encoders
- Image embeddings are projected to the language model's embedding space
- The model processes both text and image tokens together

For more information, see:

- [llama.cpp multimodal docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/mtmd)
- [llama_cpp_dart examples](https://github.com/netdur/llama_cpp_dart/tree/main/example)

## Future Improvements

To get full vision support working with streaming responses:

1. Replace the low-level FFI LlamaService with llama_cpp_dart's high-level API
2. Use `Llama` class with `generateWithMedia()` method
3. Convert `LlamaImage.fromFile()` for each image path
4. Stream the response using the built-in vision pipeline

This will enable proper multimodal processing with the mtmd library.
