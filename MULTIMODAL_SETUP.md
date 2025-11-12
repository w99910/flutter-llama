# Automatic Multimodal Model Setup

This Flutter app now automatically detects and downloads multimodal projector (mmproj) files when you download vision models from Hugging Face.

## How It Works

When you download a model, the app will:

1. **Download the main model file** (e.g., `SmolVLM-Instruct-Q4_K_M.gguf`)
2. **Search the repository** for matching mmproj files
3. **Automatically download** the mmproj file if found
4. **Prefer F16 quantization** for mmproj files (best quality)

## What Gets Downloaded

The automatic detection looks for files that:

- Contain the keyword `mmproj` in the filename
- Match the base model name (e.g., `SmolVLM-Instruct`)
- Prefer `f16` or `F16` quantization for best vision quality
- Are in GGUF format (`.gguf` extension)

## Example

If you download: `SmolVLM-Instruct-Q4_K_M.gguf`

The app will automatically find and download:

- ✅ `mmproj-SmolVLM-Instruct-f16.gguf` (preferred)
- Or `mmproj-SmolVLM-Instruct-Q8_0.gguf` (fallback)

## Supported Vision Models

The following models from Hugging Face have mmproj files:

### Recommended Starter Models

- **SmolVLM** (500M-2B) - Lightweight vision model
  - `ggml-org/SmolVLM-Instruct-GGUF`
  - `HuggingFaceTB/SmolVLM-Instruct-GGUF`

### Popular Models

- **Gemma 3** (4B-27B) - Google's multimodal model

  - `ggml-org/gemma-3-4b-it-GGUF`
  - `ggml-org/gemma-3-12b-it-GGUF`

- **Qwen2-VL** (2B-7B) - Alibaba's vision-language model

  - `ggml-org/Qwen2-VL-2B-Instruct-GGUF`
  - `ggml-org/Qwen2-VL-7B-Instruct-GGUF`

- **LLaVA 1.5** (7B-13B) - Classic vision-language model

  - `mys/ggml_llava-v1.5-7b`
  - `mys/ggml_llava-v1.5-13b`

- **Pixtral** (12B) - Mistral's vision model
  - `ggml-org/pixtral-12b-GGUF`

## Using the Feature in Code

### Simple Usage (Automatic)

```dart
// In main.dart, just set the repo and filename
String _currentRepoId = "ggml-org/SmolVLM-Instruct-GGUF";
String _currentFileName = "SmolVLM-Instruct-Q4_K_M.gguf";

// The mmproj will be automatically detected and downloaded!
```

### Manual Control

```dart
// Download with automatic mmproj detection
final result = await downloadModelWithMmproj(
  repoId: "ggml-org/SmolVLM-Instruct-GGUF",
  filename: "SmolVLM-Instruct-Q4_K_M.gguf",
  savePath: "/path/to/save/model.gguf",
  autoDownloadMmproj: true, // Set to false to disable
);

// Get paths
String modelPath = result['modelPath']!;
String? mmprojPath = result['mmprojPath']; // null if no mmproj found
```

### Check for Mmproj Files

```dart
// List all files in a repo
final files = await listRepoFiles(repoId: "ggml-org/SmolVLM-Instruct-GGUF");

// Find the mmproj file for a model
String? mmprojFile = findMmprojFile(files, "SmolVLM-Instruct-Q4_K_M.gguf");
print("Found mmproj: $mmprojFile");
```

## API Functions

### `downloadModelWithMmproj()`

Downloads a model and automatically finds/downloads its mmproj file.

**Parameters:**

- `repoId` - Hugging Face repository ID
- `filename` - Model filename
- `savePath` - Where to save the model
- `autoDownloadMmproj` - Whether to auto-download mmproj (default: true)

**Returns:** Map with `modelPath` and `mmprojPath` (or null)

### `listRepoFiles()`

Lists all files in a Hugging Face repository.

**Parameters:**

- `repoId` - Hugging Face repository ID
- `revision` - Branch/revision (default: "main")

**Returns:** List of `HFModelFile` objects

### `findMmprojFile()`

Finds the best matching mmproj file for a model.

**Parameters:**

- `files` - List of files from `listRepoFiles()`
- `modelFilename` - The model filename to match

**Returns:** Mmproj filename or null

## Notes

- **F16 is preferred** because it provides the best vision encoding quality
- **Fallback to other quantizations** if F16 is not available
- **No mmproj needed** for text-only models (they simply won't have one)
- **Cached locally** - if the mmproj file already exists, it won't be re-downloaded

## Troubleshooting

### "No mmproj file found"

This is normal for text-only models. Only vision/audio models need mmproj files.

### "Failed to download mmproj"

- Check your internet connection
- Verify the repository exists and is accessible
- Some older models may not have mmproj files in the same repo

### Model works but vision doesn't

- Ensure the mmproj file was downloaded
- Check that both files are from the same model version
- Try re-downloading both the model and mmproj

## See Also

- [VISION_MODELS.md](./VISION_MODELS.md) - List of tested vision models
- [lib/examples/multimodal_example.dart](./lib/examples/multimodal_example.dart) - Usage examples
