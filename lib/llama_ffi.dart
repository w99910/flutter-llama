import 'dart:ffi' as ffi; // Core FFI library for Pointer, Int32, etc.
import 'package:ffi/ffi.dart'; // Utility package for Utf8, calloc, etc.

// --- Handles (Opaque types) ---
final class LlamaModel extends ffi.Opaque {}

final class LlamaContext extends ffi.Opaque {}

// --- C type definitions ---
typedef LlamaToken = ffi.Int32;

// --- Native and Dart Function Signature Typedefs ---
// All string pointers are now correctly typed as ffi.Pointer<Utf8>

// llama_load_model_from_file
typedef LlamaLoadModelFromFileNative =
    ffi.Pointer<LlamaModel> Function(
      ffi.Pointer<Utf8> pathModel,
      ffi.Pointer<ffi.Void> params,
    );
typedef LlamaLoadModelFromFileDart =
    ffi.Pointer<LlamaModel> Function(
      ffi.Pointer<Utf8> pathModel,
      ffi.Pointer<ffi.Void> params,
    );

// llama_new_context_with_model
typedef LlamaNewContextWithModelNative =
    ffi.Pointer<LlamaContext> Function(
      ffi.Pointer<LlamaModel> model,
      ffi.Pointer<ffi.Void> params,
    );
typedef LlamaNewContextWithModelDart =
    ffi.Pointer<LlamaContext> Function(
      ffi.Pointer<LlamaModel> model,
      ffi.Pointer<ffi.Void> params,
    );

// llama_tokenize
typedef LlamaTokenizeNative =
    ffi.Int32 Function(
      ffi.Pointer<LlamaContext> ctx,
      ffi.Pointer<Utf8> text,
      ffi.Pointer<LlamaToken> tokens,
      ffi.Int32 nMaxTokens,
      ffi.Bool addBos,
    );
typedef LlamaTokenizeDart =
    int Function(
      ffi.Pointer<LlamaContext> ctx,
      ffi.Pointer<Utf8> text,
      ffi.Pointer<LlamaToken> tokens,
      int nMaxTokens,
      bool addBos,
    );

// llama_eval
typedef LlamaEvalNative =
    ffi.Int32 Function(
      ffi.Pointer<LlamaContext> ctx,
      ffi.Pointer<LlamaToken> tokens,
      ffi.Int32 nTokens,
      ffi.Int32 nPast,
    );
typedef LlamaEvalDart =
    int Function(
      ffi.Pointer<LlamaContext> ctx,
      ffi.Pointer<LlamaToken> tokens,
      int nTokens,
      int nPast,
    );

// llama_sample_token_greedy
typedef LlamaSampleTokenGreedyNative =
    LlamaToken Function(
      ffi.Pointer<LlamaContext> ctx,
      ffi.Pointer<ffi.Void> candidates,
    );
typedef LlamaSampleTokenGreedyDart =
    int Function(
      ffi.Pointer<LlamaContext> ctx,
      ffi.Pointer<ffi.Void> candidates,
    );

// llama_token_to_piece
typedef LlamaTokenToPieceNative =
    ffi.Pointer<Utf8> Function(ffi.Pointer<LlamaContext> ctx, LlamaToken token);
typedef LlamaTokenToPieceDart =
    ffi.Pointer<Utf8> Function(ffi.Pointer<LlamaContext> ctx, int token);

// llama_free and llama_free_model
typedef LlamaFreeNative = ffi.Void Function(ffi.Pointer<LlamaContext> ctx);
typedef LlamaFreeDart = void Function(ffi.Pointer<LlamaContext> ctx);
typedef LlamaFreeModelNative = ffi.Void Function(ffi.Pointer<LlamaModel> model);
typedef LlamaFreeModelDart = void Function(ffi.Pointer<LlamaModel> model);

// The class definition itself remains the same
class LlamaFFI {
  late final ffi.DynamicLibrary dylib;

  late final LlamaLoadModelFromFileDart llama_load_model_from_file;
  late final LlamaNewContextWithModelDart llama_new_context_with_model;
  late final LlamaTokenizeDart llama_tokenize;
  late final LlamaEvalDart llama_eval;
  late final LlamaSampleTokenGreedyDart llama_sample_token_greedy;
  late final LlamaTokenToPieceDart llama_token_to_piece;
  late final LlamaFreeDart llama_free;
  late final LlamaFreeModelDart llama_free_model;

  LlamaFFI() {
    dylib = ffi.DynamicLibrary.open('libllama.so');

    llama_load_model_from_file = dylib
        .lookup<ffi.NativeFunction<LlamaLoadModelFromFileNative>>(
          'llama_load_model_from_file',
        )
        .asFunction<LlamaLoadModelFromFileDart>();
    llama_new_context_with_model = dylib
        .lookup<ffi.NativeFunction<LlamaNewContextWithModelNative>>(
          'llama_new_context_with_model',
        )
        .asFunction<LlamaNewContextWithModelDart>();
    llama_tokenize = dylib
        .lookup<ffi.NativeFunction<LlamaTokenizeNative>>('llama_tokenize')
        .asFunction<LlamaTokenizeDart>();
    llama_eval = dylib
        .lookup<ffi.NativeFunction<LlamaEvalNative>>('llama_eval')
        .asFunction<LlamaEvalDart>();
    llama_sample_token_greedy = dylib
        .lookup<ffi.NativeFunction<LlamaSampleTokenGreedyNative>>(
          'llama_sample_token_greedy',
        )
        .asFunction<LlamaSampleTokenGreedyDart>();
    llama_token_to_piece = dylib
        .lookup<ffi.NativeFunction<LlamaTokenToPieceNative>>(
          'llama_token_to_piece',
        )
        .asFunction<LlamaTokenToPieceDart>();
    llama_free = dylib
        .lookup<ffi.NativeFunction<LlamaFreeNative>>('llama_free')
        .asFunction<LlamaFreeDart>();
    llama_free_model = dylib
        .lookup<ffi.NativeFunction<LlamaFreeModelNative>>('llama_free_model')
        .asFunction<LlamaFreeModelDart>();
  }
}
