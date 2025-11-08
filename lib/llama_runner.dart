import 'dart:isolate';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter_application_1/llama_ffi.dart'; // For Utf8

// Data class to pass initial parameters to the isolate
class LlamaRunnerParams {
  final SendPort sendPort;
  final String modelPath;
  final String prompt;

  LlamaRunnerParams({
    required this.sendPort,
    required this.modelPath,
    required this.prompt,
  });
}

// THIS IS THE ENTRY POINT FOR OUR ISOLATE
void runLlama(LlamaRunnerParams params) {
  // Use a descriptive name for your FFI bindings instance, NOT 'ffi'.
  final llama = LlamaFFI();
  final sendPort = params.sendPort;

  // Now, 'ffi' correctly refers to the dart:ffi library for types like Pointer.
  final nullptr = ffi.Pointer<ffi.Void>.fromAddress(0);

  // 1. Load Model
  sendPort.send({'type': 'log', 'data': 'Loading model...'});
  // Use the new variable 'llama' to call your functions
  final model = llama.llama_load_model_from_file(
    params.modelPath.toNativeUtf8(),
    nullptr,
  );
  if (model.address == 0) {
    sendPort.send({'type': 'error', 'data': 'Failed to load model'});
    return;
  }

  // 2. Create Context
  final context = llama.llama_new_context_with_model(model, nullptr);
  if (context.address == 0) {
    sendPort.send({'type': 'error', 'data': 'Failed to create context'});
    llama.llama_free_model(model);
    return;
  }

  // 3. Tokenize the prompt
  final promptUtf8 = params.prompt.toNativeUtf8();
  final maxTokens = params.prompt.length + 256; // Increased buffer size
  final tokens = calloc<LlamaToken>(maxTokens);
  final nTokens = llama.llama_tokenize(
    context,
    promptUtf8,
    tokens,
    maxTokens,
    true,
  );

  // 4. Evaluate the prompt
  sendPort.send({'type': 'log', 'data': 'Evaluating prompt...'});
  llama.llama_eval(context, tokens, nTokens, 0);

  // 5. Generate and stream tokens
  sendPort.send({'type': 'log', 'data': 'Generating response...'});
  var token = 0;
  for (var i = nTokens; i < maxTokens; i++) {
    token = llama.llama_sample_token_greedy(context, nullptr);

    // Llama 2 and 3 use token ID 2 for End-Of-Sequence
    // You can also check for the newline token (ID 13) to stop early if needed
    if (token == 2) break;

    // Send token piece back to main thread
    final piecePtr = llama.llama_token_to_piece(context, token);
    final piece = piecePtr.toDartString();
    sendPort.send({'type': 'token', 'data': piece});

    // Feed the token back into the model for the next iteration
    tokens[0] = token;
    llama.llama_eval(context, tokens, 1, i);
  }

  // 6. Clean up
  calloc.free(tokens);
  calloc.free(promptUtf8);
  llama.llama_free(context);
  llama.llama_free_model(model);

  sendPort.send({'type': 'done'});
}
