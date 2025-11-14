import 'dart:isolate';

import 'package:flutter_application_1/internal/llama_request.dart';
import 'package:flutter_application_1/internal/llama_isolate.dart';
import 'package:flutter_application_1/tool_calling.dart';
import 'package:path_provider/path_provider.dart';

class LlamaController {
  SendPort? _llamaSendPort;

  Future<void> initialize({String? modelPath, String? mmprojPath}) async {
    final mainReceivePort = ReceivePort();

    // Use provided path or default
    final appDocsDir = await getApplicationDocumentsDirectory();
    final String finalModelPath =
        modelPath ?? '${appDocsDir.path}/gemma-3-270m-it-Q8_0.gguf';

    // Pass the paths to the isolate during spawn.
    await Isolate.spawn(llamaIsolateEntry, {
      'port': mainReceivePort.sendPort,
      'path': finalModelPath,
      'mmprojPath': mmprojPath, // Optional mmproj path for vision models
    });

    // Wait for the isolate to send back its own SendPort
    final message = await mainReceivePort.first;
    if (message is SendPort) {
      _llamaSendPort = message;
    } else if (message is String && message == 'ERROR: MODEL_LOAD_FAILED') {
      print("Controller: The Llama isolate failed to load the model.");
      // Handle the error in the UI
    }
  }

  Future<String> runPrompt(String prompt, {GenerationParams? params}) async {
    if (_llamaSendPort == null) {
      return "Error: Llama isolate is not initialized or failed to load model.";
    }

    final responsePort = ReceivePort();
    _llamaSendPort!.send(
      LlamaRequest(
        responsePort.sendPort,
        prompt,
        params: params ?? const GenerationParams(),
      ),
    );

    final response = await responsePort.first as LlamaResponse;
    return response.text;
  }

  /// Stream tokens as they're generated from the model.
  /// Returns a Stream of token pieces.
  Stream<String> runPromptStreaming(
    String prompt, {
    GenerationParams? params,
    List<String>? imagePaths,
    ToolRegistry? toolRegistry,
    bool useTools = false,
  }) async* {
    if (_llamaSendPort == null) {
      yield "Error: Llama isolate is not initialized or failed to load model.";
      return;
    }

    final responsePort = ReceivePort();
    _llamaSendPort!.send(
      LlamaRequest(
        responsePort.sendPort,
        prompt,
        params: params ?? const GenerationParams(),
        imagePaths: imagePaths,
        toolRegistry: toolRegistry,
        useTools: useTools,
      ),
    );

    await for (final message in responsePort) {
      if (message is LlamaResponse) {
        if (message.isComplete) {
          responsePort.close();
          break;
        }
        yield message.text;
      }
    }
  }

  void dispose() {
    _llamaSendPort?.send('SHUTDOWN');
  }
}
