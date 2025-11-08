import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_application_1/internal/llama_cpp_ffi.dart';

class LlamaService {
  late final llama_cpp _bindings;
  ffi.Pointer<llama_model> _model = ffi.nullptr;
  ffi.Pointer<llama_context> _context = ffi.nullptr;

  LlamaService() {
    // Load the library based on the platform
    final dylib = _loadNativeLibrary();
    _bindings = llama_cpp(dylib);
    _bindings.llama_backend_init(); // Initialize the backend
  }

  /// Load the native library based on the platform
  ffi.DynamicLibrary _loadNativeLibrary() {
    if (Platform.isAndroid) {
      // On Android, libraries in jniLibs are automatically extracted
      // and can be loaded by name
      return ffi.DynamicLibrary.open('libllama.so');
    } else if (Platform.isIOS) {
      // On iOS, use DynamicLibrary.process() for frameworks
      return ffi.DynamicLibrary.process();
    } else if (Platform.isLinux) {
      // On Linux, specify the full path or use system library path
      return ffi.DynamicLibrary.open('libllama.so');
    } else if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('llama.dll');
    } else if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('libllama.dylib');
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  /// Loads a GGUF model from the given file path.
  /// Returns true on success, false on failure.
  bool loadModel(String modelPath) {
    if (_model != ffi.nullptr) {
      print("Model already loaded. Please free it first.");
      return false;
    }

    // 1. Get default model parameters
    final modelParams = _bindings.llama_model_default_params();
    // Force CPU-only execution (no GPU offloading)
    modelParams.n_gpu_layers = 0; // Set to 0 to disable GPU usage

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
    // contextParams.n_ctx = 2048;

    _context = _bindings.llama_new_context_with_model(_model, contextParams);

    if (_context == ffi.nullptr) {
      print("Failed to create context from model.");
      // Clean up the loaded model if context creation fails
      _bindings.llama_free_model(_model);
      _model = ffi.nullptr;
      return false;
    }

    print("Model and context loaded successfully.");
    return true;
  }

  /// Frees the loaded model and context to prevent memory leaks.
  void freeModel() {
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
  }) async {
    if (_context == ffi.nullptr) {
      throw Exception("Model not loaded. Call loadModel() first.");
    }

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
}
