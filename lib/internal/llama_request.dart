import 'dart:isolate';

// Parameters for text generation
class GenerationParams {
  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final int penaltyLastN;
  final double penaltyRepeat;
  final double penaltyFreq;
  final double penaltyPresent;
  final int maxTokens;

  const GenerationParams({
    this.temperature = 0.8,
    this.topK = 40,
    this.topP = 0.95,
    this.minP = 0.05,
    this.penaltyLastN = 64,
    this.penaltyRepeat = 1.3,
    this.penaltyFreq = 0.2,
    this.penaltyPresent = 0.1,
    this.maxTokens = 4096,
  });
}

// Message to send a prompt to the isolate
class LlamaRequest {
  final SendPort port; // Port to send the response back on
  final String prompt;
  final GenerationParams params;
  final List<String>? imagePaths; // Optional image paths for vision models

  LlamaRequest(
    this.port,
    this.prompt, {
    this.params = const GenerationParams(),
    this.imagePaths,
  });
}

// Message to send the generated response back to the UI
class LlamaResponse {
  final String text;
  final bool isComplete;
  LlamaResponse(this.text, {this.isComplete = false});
}
