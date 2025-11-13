import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:convert';
import 'dart:io' show Platform, File;
import 'package:image/image.dart' as img;

import 'package:flutter_application_1/internal/llama_cpp_ffi.dart';

class LlamaService {
  late final llama_cpp _bindings;
  late final llama_cpp _mtmdBindings; // Separate bindings for mtmd library
  ffi.Pointer<llama_model> _model = ffi.nullptr;
  ffi.Pointer<llama_context> _context = ffi.nullptr;
  ffi.Pointer<mtmd_context> _mtmdContext = ffi.nullptr;

  bool get supportsVision => _mtmdContext != ffi.nullptr;

  LlamaService() {
    // Load the main llama library
    final llamaLib = _loadNativeLibrary('libllama.so');
    _bindings = llama_cpp(llamaLib);

    // Try to load mtmd library separately
    try {
      final mtmdLib = _loadNativeLibrary('libmtmd.so');
      _mtmdBindings = llama_cpp(mtmdLib);
      print("✅ Multimodal library (libmtmd.so) loaded successfully");
    } catch (e) {
      print("⚠️  Multimodal library not available: $e");
      print("   Vision/audio features will be disabled.");
      // Use main library as fallback
      _mtmdBindings = _bindings;
    }

    _bindings.llama_backend_init(); // Initialize the backend
  }

  /// Load the native library based on the platform
  ffi.DynamicLibrary _loadNativeLibrary(String libraryName) {
    if (Platform.isAndroid) {
      // On Android, libraries in jniLibs are automatically extracted
      // and can be loaded by name
      return ffi.DynamicLibrary.open(libraryName);
    } else if (Platform.isIOS) {
      // On iOS, use DynamicLibrary.process() for frameworks
      return ffi.DynamicLibrary.process();
    } else if (Platform.isLinux) {
      // On Linux, specify the full path or use system library path
      return ffi.DynamicLibrary.open(libraryName);
    } else if (Platform.isWindows) {
      final winName = libraryName
          .replaceAll('.so', '.dll')
          .replaceAll('lib', '');
      return ffi.DynamicLibrary.open(winName);
    } else if (Platform.isMacOS) {
      final macName = libraryName.replaceAll('.so', '.dylib');
      return ffi.DynamicLibrary.open(macName);
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  /// Loads a GGUF model from the given file path.
  /// [mmprojPath] - Optional path to multimodal projector for vision models
  /// Returns true on success, false on failure.
  bool loadModel(String modelPath, {String? mmprojPath}) {
    print("═══════════════════════════════════════");
    print("LlamaService.loadModel called:");
    print("  modelPath: $modelPath");
    print("  mmprojPath: ${mmprojPath ?? 'null'}");
    print("═══════════════════════════════════════");

    if (_model != ffi.nullptr) {
      print("Model already loaded. Please free it first.");
      return false;
    }

    // 1. Get default model parameters
    final modelParams = _bindings.llama_model_default_params();
    // Enable GPU offloading for better performance
    // For vision models, GPU is essential for processing images in reasonable time
    modelParams.n_gpu_layers = 999; // Offload as many layers as possible to GPU
    print(
      "GPU offloading enabled: n_gpu_layers=999 (vision models require GPU for acceptable performance)",
    );

    // Convert the Dart string path to a C-style string (Pointer<Char>)
    final pathPtr = modelPath.toNativeUtf8();

    // 2. Load the GGUF model from the file
    _model = _bindings.llama_load_model_from_file(pathPtr.cast(), modelParams);

    // Free the C string pointer
    malloc.free(pathPtr);

    if (_model == ffi.nullptr) {
      print("Failed to load model from path: $modelPath");
      return false;
    }

    // 3. Create a context from the loaded model
    final contextParams = _bindings.llama_context_default_params();
    // Customize context params if needed, e.g., context size
    // Set a larger context size for vision models to accommodate image embeddings
    // Vision models typically need 2048-4096 tokens for images + prompt + response
    contextParams.n_ctx = mmprojPath != null ? 4096 : 2048;

    // CRITICAL: Set n_ubatch (micro-batch size) for vision models
    // Image embeddings can be 576+ tokens, so we need a larger ubatch size
    // This must be large enough to hold at least one image's worth of embeddings
    if (mmprojPath != null) {
      contextParams.n_ubatch = 2048; // Large enough for image embeddings
    }

    print("Setting context size to: ${contextParams.n_ctx}");
    if (mmprojPath != null) {
      print(
        "Setting n_ubatch to: ${contextParams.n_ubatch} (for vision model)",
      );
    }

    _context = _bindings.llama_new_context_with_model(_model, contextParams);

    if (_context == ffi.nullptr) {
      print("Failed to create context from model.");
      // Clean up the loaded model if context creation fails
      _bindings.llama_free_model(_model);
      _model = ffi.nullptr;
      return false;
    }

    // Load vision projector if provided
    if (mmprojPath != null) {
      print("Loading multimodal projector from: $mmprojPath");

      final mmprojPathPtr = mmprojPath.toNativeUtf8();

      // Get default mtmd parameters using the mtmd library
      final mtmdParams = _mtmdBindings.mtmd_context_params_default();
      mtmdParams.use_gpu =
          true; // Enable GPU for image processing (CRITICAL for performance)
      mtmdParams.print_timings = true;
      mtmdParams.n_threads = 4; // Adjust as needed
      print("Multimodal projector GPU enabled for fast image processing");

      // Set the media marker to match the chat template
      // SmolVLM and other vision models use <image> token
      final markerPtr = '<image>'.toNativeUtf8();
      mtmdParams.media_marker = markerPtr.cast();

      // Initialize multimodal context using the mtmd library
      _mtmdContext = _mtmdBindings.mtmd_init_from_file(
        mmprojPathPtr.cast(),
        _model,
        mtmdParams,
      );

      malloc.free(mmprojPathPtr);
      malloc.free(markerPtr);

      if (_mtmdContext == ffi.nullptr) {
        print(
          "Failed to load multimodal projector. Continuing without vision support.",
        );
      } else {
        final hasVision = _mtmdBindings.mtmd_support_vision(_mtmdContext);
        final hasAudio = _mtmdBindings.mtmd_support_audio(_mtmdContext);
        print("Multimodal projector loaded successfully!");
        print("  - Vision support: $hasVision");
        print("  - Audio support: $hasAudio");
        print("  - Using marker: <image>");
        print("  - Audio support: $hasAudio");
      }
    }

    print("Model and context loaded successfully.");
    return true;
  }

  /// Frees the loaded model and context to prevent memory leaks.
  void freeModel() {
    if (_mtmdContext != ffi.nullptr) {
      _mtmdBindings.mtmd_free(_mtmdContext);
      _mtmdContext = ffi.nullptr;
    }
    if (_context != ffi.nullptr) {
      _bindings.llama_free(_context);
      _context = ffi.nullptr;
    }
    if (_model != ffi.nullptr) {
      _bindings.llama_free_model(_model);
      _model = ffi.nullptr;
    }
    print("Model and context freed.");
  }

  void dispose() {
    freeModel();
    _bindings.llama_backend_free();
  }
  // ... (constructor and loadModel methods from previous answer) ...

  /// Helper function to tokenize text.
  /// Returns a Dart List of integers (token IDs).
  List<int> _tokenize(String text, {bool addBos = true, bool special = false}) {
    final vocab = _bindings.llama_model_get_vocab(_model);
    final textPtr = text.toNativeUtf8();

    // Allocate memory for the tokens. Add a safety margin.
    final tokens = malloc<llama_token>(text.length + 64);

    final nTokens = _bindings.llama_tokenize(
      vocab,
      textPtr.cast(),
      text.length,
      tokens,
      text.length + 64,
      addBos,
      special,
    );

    if (nTokens < 0) {
      malloc.free(tokens);
      malloc.free(textPtr);
      throw Exception(
        "Failed to tokenize: buffer too small or text contains invalid characters.",
      );
    }

    // FIX: Use 'int' for the list type.
    final tokenList = List<int>.from(tokens.asTypedList(nTokens));

    malloc.free(tokens);
    malloc.free(textPtr);
    return tokenList;
  }

  /// Helper to convert a single token to bytes (not decoded as UTF-8 yet)
  List<int> _tokenToBytes(int token) {
    final vocab = _bindings.llama_model_get_vocab(_model);
    // Increase buffer size to handle longer token pieces
    const bufferSize = 64;
    final buffer = malloc<ffi.Uint8>(bufferSize).cast<ffi.Char>();
    final nBytes = _bindings.llama_token_to_piece(
      vocab,
      token,
      buffer,
      bufferSize,
      0,
      false,
    );
    if (nBytes < 0) {
      malloc.free(buffer);
      throw Exception(
        "Failed to convert token to piece (token: $token, nBytes: $nBytes)",
      );
    }

    // Copy bytes to a Dart list
    final bytes = <int>[];
    for (int i = 0; i < nBytes; i++) {
      bytes.add(buffer.cast<ffi.Uint8>()[i]);
    }

    malloc.free(buffer);
    return bytes;
  }

  /// Helper to resize image to 480p (854x480) if it's larger
  /// Returns the path to the resized image (or original if no resize needed)
  Future<String> _resizeImageTo480pIfNeeded(String imagePath) async {
    try {
      // Read the image file
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();

      // Decode the image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        print("Warning: Could not decode image $imagePath, using original");
        return imagePath;
      }

      final width = image.width;
      final height = image.height;

      // Check if resizing is needed (if either dimension exceeds 480p)
      // 480p is typically 854x480 (16:9) but we'll use 480 as the max for the shorter side
      const maxDimension = 480;

      if (width <= maxDimension && height <= maxDimension) {
        print(
          "Image $imagePath is already <= 480p (${width}x${height}), no resize needed",
        );
        return imagePath;
      }

      // Calculate new dimensions maintaining aspect ratio
      int newWidth, newHeight;
      if (width > height) {
        // Landscape: limit height to maxDimension
        newHeight = maxDimension;
        newWidth = (width * maxDimension / height).round();
      } else {
        // Portrait or square: limit width to maxDimension
        newWidth = maxDimension;
        newHeight = (height * maxDimension / width).round();
      }

      print(
        "Resizing image from ${width}x${height} to ${newWidth}x${newHeight}",
      );

      // Resize the image
      final resized = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );

      // Save to a temporary file
      final tempDir = await File(imagePath).parent.path;
      final tempPath =
          '$tempDir/resized_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final resizedFile = File(tempPath);
      await resizedFile.writeAsBytes(img.encodeJpg(resized, quality: 85));

      print("Resized image saved to: $tempPath");
      return tempPath;
    } catch (e) {
      print("Error resizing image $imagePath: $e");
      print("Falling back to original image");
      return imagePath;
    }
  }

  Future<String> runPrompt(String prompt) async {
    if (_context == ffi.nullptr) {
      throw Exception("Model not loaded. Call loadModel() first.");
    }

    // Clear the KV cache to avoid contamination from previous prompts
    final memory = _bindings.llama_get_memory(_context);
    _bindings.llama_memory_clear(memory, true);

    // Use special=true to properly parse chat template tokens like <|im_start|>, <|im_end|>
    // Set addBos=false since chat templates handle BOS themselves
    final tokensList = _tokenize(prompt, addBos: false, special: true);
    final nCtx = _bindings.llama_n_ctx(_context);
    final vocab = _bindings.llama_model_get_vocab(_model);

    if (tokensList.length > nCtx) {
      throw Exception(
        "Prompt is too long (${tokensList.length} tokens), context size is $nCtx",
      );
    }

    final batch = _bindings.llama_batch_init(tokensList.length, 0, 1);
    batch.n_tokens = tokensList.length;

    for (int i = 0; i < batch.n_tokens; i++) {
      (batch.token + i).value = tokensList[i];
      (batch.pos + i).value = i;
      (batch.n_seq_id + i).value = 1;
      (batch.seq_id + i).value.value = 0;
      (batch.logits + i).value = 0;
    }

    (batch.logits + batch.n_tokens - 1).value = 1;

    if (_bindings.llama_decode(_context, batch) != 0) {
      print("llama_decode failed during prompt processing");
      _bindings.llama_batch_free(batch);
      return "";
    }
    _bindings.llama_batch_free(batch);

    // Setup the samplers in the correct order
    final sparams = _bindings.llama_sampler_chain_default_params();
    final smpl = _bindings.llama_sampler_chain_init(sparams);

    // 1. Repetition penalties (prevents hallucination loops)
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_penalties(
        64, // penalty_last_n: consider the last 64 tokens
        1.1, // penalty_repeat: apply a 1.1x penalty to repeated tokens
        0.0, // penalty_freq: no frequency penalty
        0.0, // penalty_present: no presence penalty
      ),
    );

    // 2. Top-k sampling
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_top_k(40),
    );

    // 3. Top-p (nucleus) sampling
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_top_p(0.95, 1),
    );

    // 4. Temperature
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_temp(0.8),
    );

    // 5. Distribution sampler (replaces greedy)
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_dist(0),
    );

    final eosToken = _bindings.llama_token_eos(vocab);
    final byteBuffer = <int>[]; // Buffer for raw bytes

    // The main generation loop
    for (int i = tokensList.length; i < nCtx; i++) {
      final int token = _bindings.llama_sampler_sample(smpl, _context, -1);
      _bindings.llama_sampler_accept(smpl, token);

      if (token == eosToken) {
        break;
      }

      byteBuffer.addAll(_tokenToBytes(token));

      final nextBatch = _bindings.llama_batch_init(1, 0, 1);
      nextBatch.n_tokens = 1;
      (nextBatch.token).value = token;
      (nextBatch.pos).value = i;
      (nextBatch.n_seq_id).value = 1;
      (nextBatch.seq_id).value.value = 0;
      (nextBatch.logits).value = 1;

      if (_bindings.llama_decode(_context, nextBatch) != 0) {
        print("llama_decode failed during generation");
        _bindings.llama_batch_free(nextBatch);
        break;
      }
      _bindings.llama_batch_free(nextBatch);
    }

    _bindings.llama_sampler_free(smpl);

    // Decode all bytes at once with proper UTF-8 handling
    return utf8.decode(byteBuffer, allowMalformed: true);
  }

  /// Runs a prompt and streams tokens as they're generated.
  /// The [onToken] callback is called for each token piece.
  /// [imagePaths] - Optional list of image file paths for vision models
  Future<String> runPromptStreaming(
    String prompt,
    void Function(String tokenPiece) onToken, {
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    double minP = 0.05,
    int penaltyLastN = 64,
    double penaltyRepeat = 1.3,
    double penaltyFreq = 0.2,
    double penaltyPresent = 0.1,
    int maxTokens = 2048 * 4,
    List<String>? imagePaths,
  }) async {
    if (_context == ffi.nullptr) {
      throw Exception("Model not loaded. Call loadModel() first.");
    }

    // Check if images are provided but multimodal is not supported
    if (imagePaths != null && imagePaths.isNotEmpty) {
      if (_mtmdContext == ffi.nullptr) {
        throw Exception(
          "Images provided but multimodal projector not loaded. "
          "Call loadModel() with mmprojPath parameter.",
        );
      }

      if (!_mtmdBindings.mtmd_support_vision(_mtmdContext)) {
        throw Exception(
          "Loaded multimodal projector does not support vision input.",
        );
      }

      print("Processing prompt with ${imagePaths.length} image(s)");
      return _runPromptStreamingWithImages(
        prompt,
        imagePaths,
        onToken,
        temperature: temperature,
        topK: topK,
        topP: topP,
        minP: minP,
        penaltyLastN: penaltyLastN,
        penaltyRepeat: penaltyRepeat,
        penaltyFreq: penaltyFreq,
        penaltyPresent: penaltyPresent,
        maxTokens: maxTokens,
      );
    }

    // Text-only processing (original implementation)
    return _runPromptStreamingTextOnly(
      prompt,
      onToken,
      temperature: temperature,
      topK: topK,
      topP: topP,
      minP: minP,
      penaltyLastN: penaltyLastN,
      penaltyRepeat: penaltyRepeat,
      penaltyFreq: penaltyFreq,
      penaltyPresent: penaltyPresent,
      maxTokens: maxTokens,
    );
  }

  /// Internal method: Text-only streaming (original implementation)
  Future<String> _runPromptStreamingTextOnly(
    String prompt,
    void Function(String tokenPiece) onToken, {
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    double minP = 0.05,
    int penaltyLastN = 64,
    double penaltyRepeat = 1.3,
    double penaltyFreq = 0.2,
    double penaltyPresent = 0.1,
    int maxTokens = 2048 * 4,
  }) async {
    // CRITICAL: Clear the KV cache before each prompt to avoid contamination
    final memory = _bindings.llama_get_memory(_context);
    _bindings.llama_memory_clear(memory, true);

    // Use special=true to properly parse chat template tokens like <|im_start|>, <|im_end|>
    // Set addBos=false since chat templates handle BOS themselves
    final tokensList = _tokenize(prompt, addBos: false, special: true);
    final nCtx = _bindings.llama_n_ctx(_context);
    final vocab = _bindings.llama_model_get_vocab(_model);

    if (tokensList.length > nCtx) {
      throw Exception(
        "Prompt is too long (${tokensList.length} tokens), context size is $nCtx",
      );
    }

    final batch = _bindings.llama_batch_init(tokensList.length, 0, 1);
    batch.n_tokens = tokensList.length;

    for (int i = 0; i < batch.n_tokens; i++) {
      (batch.token + i).value = tokensList[i];
      (batch.pos + i).value = i;
      (batch.n_seq_id + i).value = 1;
      (batch.seq_id + i).value.value = 0;
      (batch.logits + i).value = 0;
    }

    (batch.logits + batch.n_tokens - 1).value = 1;

    if (_bindings.llama_decode(_context, batch) != 0) {
      print("llama_decode failed during prompt processing");
      _bindings.llama_batch_free(batch);
      return "";
    }
    _bindings.llama_batch_free(batch);

    // Setup the samplers
    final sparams = _bindings.llama_sampler_chain_default_params();
    final smpl = _bindings.llama_sampler_chain_init(sparams);

    // Add samplers in the correct order for best results:
    // 1. Repetition penalties (prevents loops)
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_penalties(
        penaltyLastN,
        penaltyRepeat,
        penaltyFreq,
        penaltyPresent,
      ),
    );

    // 2. Top-k sampling (limits to top K tokens)
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_top_k(topK),
    );

    // 3. Top-p (nucleus) sampling
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_top_p(topP, 1),
    );

    // 4. Min-p sampling (if minP > 0)
    if (minP > 0.0) {
      _bindings.llama_sampler_chain_add(
        smpl,
        _bindings.llama_sampler_init_min_p(minP, 1),
      );
    }

    // 5. Temperature (controls randomness)
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_temp(temperature),
    );

    // 6. Final sampler - use dist for sampling from the distribution
    _bindings.llama_sampler_chain_add(
      smpl,
      _bindings.llama_sampler_init_dist(0), // 0 = random seed
    );

    final eosToken = _bindings.llama_token_eos(vocab);
    final byteBuffer = <int>[]; // Buffer for all bytes

    // Buffer to accumulate bytes until we have valid UTF-8
    final streamBuffer = <int>[];

    String decodeAndFlush(List<int> bytes, {bool final_ = false}) {
      streamBuffer.addAll(bytes);

      // Try to decode - find the last valid UTF-8 sequence
      String result = '';
      int validEnd = streamBuffer.length;

      while (validEnd > 0) {
        try {
          result = utf8.decode(streamBuffer.sublist(0, validEnd));
          // If successful, remove the decoded bytes from the buffer
          if (validEnd < streamBuffer.length && !final_) {
            streamBuffer.removeRange(0, validEnd);
          } else {
            streamBuffer.clear();
          }
          break;
        } catch (e) {
          // Try with one less byte
          validEnd--;
        }
      }

      return result;
    }

    // The main generation loop - limit to maxTokens
    final maxGenTokens = tokensList.length + maxTokens;
    final loopLimit = maxGenTokens < nCtx ? maxGenTokens : nCtx;

    for (int i = tokensList.length; i < loopLimit; i++) {
      final int token = _bindings.llama_sampler_sample(smpl, _context, -1);
      _bindings.llama_sampler_accept(smpl, token);

      if (token == eosToken) {
        break;
      }

      final tokenBytes = _tokenToBytes(token);
      byteBuffer.addAll(tokenBytes);

      // Decode and send any complete UTF-8 sequences
      final decoded = decodeAndFlush(tokenBytes);
      if (decoded.isNotEmpty) {
        onToken(decoded);
      }

      final nextBatch = _bindings.llama_batch_init(1, 0, 1);
      nextBatch.n_tokens = 1;
      (nextBatch.token).value = token;
      (nextBatch.pos).value = i;
      (nextBatch.n_seq_id).value = 1;
      (nextBatch.seq_id).value.value = 0;
      (nextBatch.logits).value = 1;

      if (_bindings.llama_decode(_context, nextBatch) != 0) {
        print("llama_decode failed during generation");
        _bindings.llama_batch_free(nextBatch);
        break;
      }
      _bindings.llama_batch_free(nextBatch);
    }

    // Flush any remaining bytes
    if (streamBuffer.isNotEmpty) {
      final remaining = decodeAndFlush([], final_: true);
      if (remaining.isNotEmpty) {
        onToken(remaining);
      }
    }

    _bindings.llama_sampler_free(smpl);

    // Return the fully decoded string
    return utf8.decode(byteBuffer, allowMalformed: true);
  }

  /// Internal method: Streaming with image support
  Future<String> _runPromptStreamingWithImages(
    String prompt,
    List<String> imagePaths,
    void Function(String tokenPiece) onToken, {
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    double minP = 0.05,
    int penaltyLastN = 64,
    double penaltyRepeat = 1.3,
    double penaltyFreq = 0.2,
    double penaltyPresent = 0.1,
    int maxTokens = 2048 * 4,
  }) async {
    // CRITICAL: Clear the KV cache before each prompt
    final memory = _bindings.llama_get_memory(_context);
    _bindings.llama_memory_clear(memory, true);

    // Load images as bitmaps
    final bitmaps = <ffi.Pointer<mtmd_bitmap>>[];
    final bitmapPtrs = <ffi.Pointer<ffi.Pointer<mtmd_bitmap>>>[];
    final resizedImagePaths = <String>[]; // Track resized images for cleanup

    try {
      for (final imagePath in imagePaths) {
        // Resize image to 480p if needed
        final processedImagePath = await _resizeImageTo480pIfNeeded(imagePath);
        if (processedImagePath != imagePath) {
          resizedImagePaths.add(processedImagePath);
        }

        final imagePathPtr = processedImagePath.toNativeUtf8();
        final bitmap = _mtmdBindings.mtmd_helper_bitmap_init_from_file(
          _mtmdContext,
          imagePathPtr.cast(),
        );
        malloc.free(imagePathPtr);

        if (bitmap == ffi.nullptr) {
          throw Exception("Failed to load image: $imagePath");
        }

        bitmaps.add(bitmap);
        print(
          "Loaded image: $imagePath (${_mtmdBindings.mtmd_bitmap_get_nx(bitmap)}x${_mtmdBindings.mtmd_bitmap_get_ny(bitmap)})",
        );
      }

      // Create array of bitmap pointers
      final bitmapArrayPtr = malloc<ffi.Pointer<mtmd_bitmap>>(bitmaps.length);
      for (int i = 0; i < bitmaps.length; i++) {
        bitmapArrayPtr[i] = bitmaps[i];
      }
      bitmapPtrs.add(bitmapArrayPtr);

      // Prepare input text structure
      final inputTextPtr = malloc<mtmd_input_text>();
      final promptPtr = prompt.toNativeUtf8();
      inputTextPtr.ref.text = promptPtr.cast();
      inputTextPtr.ref.add_special = false;
      inputTextPtr.ref.parse_special = true;

      // Debug: Count image markers in prompt
      final imageMarkerCount = '<image>'.allMatches(prompt).length;
      print(
        "Prompt has $imageMarkerCount <image> marker(s), ${bitmaps.length} bitmap(s) loaded",
      );
      if (imageMarkerCount != bitmaps.length) {
        print(
          "WARNING: Mismatch detected! This will cause tokenization to fail.",
        );
        print(
          "Prompt preview: ${prompt.substring(0, prompt.length < 200 ? prompt.length : 200)}...",
        );
      }

      // Tokenize with images
      final chunksPtr = _mtmdBindings.mtmd_input_chunks_init();
      final tokenizeResult = _mtmdBindings.mtmd_tokenize(
        _mtmdContext,
        chunksPtr,
        inputTextPtr,
        bitmapArrayPtr,
        bitmaps.length,
      );

      if (tokenizeResult != 0) {
        String errorMsg =
            "Failed to tokenize with images. Error code: $tokenizeResult";
        if (tokenizeResult == 1) {
          errorMsg +=
              "\n  Reason: Number of bitmaps (${bitmaps.length}) doesn't match number of <image> markers ($imageMarkerCount)";
        } else if (tokenizeResult == 2) {
          errorMsg += "\n  Reason: Image preprocessing error";
        }
        throw Exception(errorMsg);
      }

      final nChunks = _mtmdBindings.mtmd_input_chunks_size(chunksPtr);
      print("Tokenized into $nChunks chunks");

      // Use helper function to evaluate all chunks (text and images)
      // This handles batching, encoding images, and proper attention patterns
      final nPastPtr = malloc<llama_pos>();
      nPastPtr.value = 0;

      final nCtx = _bindings.llama_n_ctx(_context);
      final nUbatch = _bindings.llama_n_ubatch(_context);
      // For vision models, use a larger batch size to accommodate image embeddings
      // The batch size should be at least as large as n_ubatch to process images efficiently
      final nBatch = nUbatch; // Use n_ubatch as batch size for vision models
      final vocab = _bindings.llama_model_get_vocab(
        _model,
      ); // Needed for EOS token later

      print(
        "Context info: n_ctx=$nCtx, n_ubatch=$nUbatch, n_batch=$nBatch, n_chunks=$nChunks",
      );
      print("Evaluating chunks with mtmd_helper");

      final evalResult = _mtmdBindings.mtmd_helper_eval_chunks(
        _mtmdContext,
        _context,
        chunksPtr,
        0, // n_past starts at 0
        0, // seq_id
        nBatch,
        true, // logits_last
        nPastPtr,
      );

      if (evalResult != 0) {
        malloc.free(nPastPtr);
        throw Exception(
          "Failed to evaluate chunks. Error code: $evalResult. "
          "Context: n_ctx=$nCtx, n_ubatch=$nUbatch, n_batch=$nBatch, n_chunks=$nChunks. "
          "Vision models need sufficient n_ubatch to hold image embeddings (typically 2048+).",
        );
      }

      final nPast = nPastPtr.value;
      malloc.free(nPastPtr);

      print("All chunks processed. Starting generation from position $nPast");

      // Setup the samplers
      final sparams = _bindings.llama_sampler_chain_default_params();
      final smpl = _bindings.llama_sampler_chain_init(sparams);

      _bindings.llama_sampler_chain_add(
        smpl,
        _bindings.llama_sampler_init_penalties(
          penaltyLastN,
          penaltyRepeat,
          penaltyFreq,
          penaltyPresent,
        ),
      );

      _bindings.llama_sampler_chain_add(
        smpl,
        _bindings.llama_sampler_init_top_k(topK),
      );

      _bindings.llama_sampler_chain_add(
        smpl,
        _bindings.llama_sampler_init_top_p(topP, 1),
      );

      if (minP > 0.0) {
        _bindings.llama_sampler_chain_add(
          smpl,
          _bindings.llama_sampler_init_min_p(minP, 1),
        );
      }

      _bindings.llama_sampler_chain_add(
        smpl,
        _bindings.llama_sampler_init_temp(temperature),
      );

      _bindings.llama_sampler_chain_add(
        smpl,
        _bindings.llama_sampler_init_dist(0),
      );

      final eosToken = _bindings.llama_token_eos(vocab);
      final byteBuffer = <int>[];
      final streamBuffer = <int>[];

      String decodeAndFlush(List<int> bytes, {bool final_ = false}) {
        streamBuffer.addAll(bytes);
        String result = '';
        int validEnd = streamBuffer.length;

        while (validEnd > 0) {
          try {
            result = utf8.decode(streamBuffer.sublist(0, validEnd));
            if (validEnd < streamBuffer.length && !final_) {
              streamBuffer.removeRange(0, validEnd);
            } else {
              streamBuffer.clear();
            }
            break;
          } catch (e) {
            validEnd--;
          }
        }

        return result;
      }

      // Generation loop
      final maxGenTokens = nPast + maxTokens;
      final loopLimit = maxGenTokens < nCtx ? maxGenTokens : nCtx;

      for (int i = nPast; i < loopLimit; i++) {
        final int token = _bindings.llama_sampler_sample(smpl, _context, -1);
        _bindings.llama_sampler_accept(smpl, token);

        if (token == eosToken) {
          break;
        }

        final tokenBytes = _tokenToBytes(token);
        byteBuffer.addAll(tokenBytes);

        final decoded = decodeAndFlush(tokenBytes);
        if (decoded.isNotEmpty) {
          onToken(decoded);
        }

        final nextBatch = _bindings.llama_batch_init(1, 0, 1);
        nextBatch.n_tokens = 1;
        (nextBatch.token).value = token;
        (nextBatch.pos).value = i;
        (nextBatch.n_seq_id).value = 1;
        (nextBatch.seq_id).value.value = 0;
        (nextBatch.logits).value = 1;

        if (_bindings.llama_decode(_context, nextBatch) != 0) {
          print("llama_decode failed during generation");
          _bindings.llama_batch_free(nextBatch);
          break;
        }
        _bindings.llama_batch_free(nextBatch);
      }

      if (streamBuffer.isNotEmpty) {
        final remaining = decodeAndFlush([], final_: true);
        if (remaining.isNotEmpty) {
          onToken(remaining);
        }
      }

      _bindings.llama_sampler_free(smpl);
      _mtmdBindings.mtmd_input_chunks_free(chunksPtr);
      malloc.free(promptPtr);
      malloc.free(inputTextPtr);

      return utf8.decode(byteBuffer, allowMalformed: true);
    } finally {
      // Cleanup bitmaps
      for (final bitmap in bitmaps) {
        _mtmdBindings.mtmd_bitmap_free(bitmap);
      }
      for (final ptr in bitmapPtrs) {
        malloc.free(ptr);
      }

      // Delete temporary resized images
      for (final resizedPath in resizedImagePaths) {
        try {
          final file = File(resizedPath);
          if (await file.exists()) {
            await file.delete();
            print("Cleaned up resized image: $resizedPath");
          }
        } catch (e) {
          print("Error cleaning up resized image $resizedPath: $e");
        }
      }
    }
  }
}
