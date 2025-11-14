import 'dart:isolate';
import 'package:flutter_application_1/internal/llama_service.dart'; // Your LlamaService class
import 'package:flutter_application_1/internal/llama_request.dart';

// This is the entry point for our new isolate.
void llamaIsolateEntry(Map<String, dynamic> args) async {
  final mainSendPort = args['port'] as SendPort;
  final modelPath =
      args['path'] as String; // Use the path passed from the main isolate
  final mmprojPath = args['mmprojPath'] as String?; // Optional mmproj path

  final isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  // Initialize the service and load the model ONCE.
  final llamaService = LlamaService();
  final success = llamaService.loadModel(modelPath, mmprojPath: mmprojPath);

  if (!success) {
    print("Llama Isolate: FAILED to load model at '$modelPath'.");
    // Optionally send an error message back to the main isolate
    mainSendPort.send('ERROR: MODEL_LOAD_FAILED');
    return; // Exit the isolate if the model fails to load
  }

  print("Llama Isolate: Model loaded and ready.");

  // Listen for requests from the main thread (this part remains the same)
  await for (final message in isolateReceivePort) {
    if (message is LlamaRequest) {
      final prompt = message.prompt;
      final params = message.params;
      final imagePaths = message.imagePaths;
      final toolRegistry = message.toolRegistry;
      final useTools = message.useTools;
      
      print("Llama Isolate: Received prompt: '$prompt'");
      if (imagePaths != null && imagePaths.isNotEmpty) {
        print(
          "Llama Isolate: Received ${imagePaths.length} image(s): $imagePaths",
        );
      }
      if (useTools && toolRegistry != null) {
        print("Llama Isolate: Tool calling enabled");
      }

      // Check if we should use tool calling
      if (useTools && toolRegistry != null) {
        // Use tool calling
        await llamaService.runPromptWithTools(
          prompt,
          (tokenPiece) {
            message.port.send(LlamaResponse(tokenPiece, isComplete: false));
          },
          toolRegistry,
          temperature: params.temperature,
          topK: params.topK,
          topP: params.topP,
          minP: params.minP,
          penaltyLastN: params.penaltyLastN,
          penaltyRepeat: params.penaltyRepeat,
          penaltyFreq: params.penaltyFreq,
          penaltyPresent: params.penaltyPresent,
          maxTokens: params.maxTokens,
          imagePaths: imagePaths,
        );
      } else {
        // Normal streaming without tools
        await llamaService.runPromptStreaming(
          prompt,
          (tokenPiece) {
            message.port.send(LlamaResponse(tokenPiece, isComplete: false));
          },
          temperature: params.temperature,
          topK: params.topK,
          topP: params.topP,
          minP: params.minP,
          penaltyLastN: params.penaltyLastN,
          penaltyRepeat: params.penaltyRepeat,
          penaltyFreq: params.penaltyFreq,
          penaltyPresent: params.penaltyPresent,
          maxTokens: params.maxTokens,
          imagePaths: imagePaths,
        );
      }

      // Send final completion signal
      message.port.send(LlamaResponse('', isComplete: true));
    } else if (message == 'SHUTDOWN') {
      print("Llama Isolate: Shutting down...");
      llamaService.dispose();
      Isolate.current.kill();
    }
  }
}
