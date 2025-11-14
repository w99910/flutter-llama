import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/internal/auto_function_executor.dart';

/// Simple demonstration of automatic function calling
///
/// User asks questions, and functions are called automatically when needed:
/// - "What's 1+1?" → automatically calls calculate function
/// - "What time is it?" → automatically calls get_current_time
/// - "Pick a random number between 1 and 100" → calls generate_random_number
void main() async {
  print("═══════════════════════════════════════");
  print("🤖 Automatic Function Calling Demo");
  print("═══════════════════════════════════════\n");

  // 1. Initialize LlamaService
  final llamaService = LlamaService();

  // 2. Load your model
  print("📦 Loading model...");
  final modelPath = '/path/to/your/model.gguf'; // CHANGE THIS
  final success = llamaService.loadModel(modelPath);

  if (!success) {
    print("❌ Failed to load model");
    return;
  }

  print("✅ Model loaded successfully\n");

  // 3. Initialize auto function executor
  final executor = AutoFunctionExecutor(llamaService);

  print("🔧 Available functions:");
  for (final funcName in executor.getAvailableFunctions()) {
    final func = executor.getFunction(funcName);
    print("  - $funcName: ${func?.description}");
  }
  print("\n");

  // 4. Test automatic function calling with various queries
  final testQueries = [
    "What's 1+1?",
    "Calculate 25 * 48 + 120",
    "What's the square root of 144?",
    "What time is it now?",
    "Pick a random number between 1 and 100",
    "Calculate (5 + 3) * 2 - 4",
    "Hello! How are you?", // No function call needed
  ];

  for (final query in testQueries) {
    print("═══════════════════════════════════════");
    print("👤 User: $query");
    print("═══════════════════════════════════════");
    print("🤖 Assistant: ");

    try {
      await executor.processUserInput(
        query,
        (token) {
          // Stream the response token by token
          print(token); // In Flutter, you'd update UI here
        },
        verbose: true, // Show detailed function call logs
      );

      print("\n"); // Add spacing between queries
    } catch (e) {
      print("\n❌ Error: $e\n");
    }
  }

  // 5. Example: Multi-turn conversation with function calls
  print("\n═══════════════════════════════════════");
  print("💬 Multi-turn Conversation Example");
  print("═══════════════════════════════════════\n");

  final conversationHistory = <Map<String, String>>[];

  // Turn 1
  print("👤 User: Calculate 5 * 5");
  print("🤖 Assistant: ");
  await executor.processUserInput(
    "Calculate 5 * 5",
    (token) => print(token),
    conversationHistory: conversationHistory,
  );

  print("\n\n👤 User: Now multiply that by 2");
  print("🤖 Assistant: ");
  await executor.processUserInput(
    "Now multiply that by 2",
    (token) => print(token),
    conversationHistory: conversationHistory,
  );

  print("\n");

  // 6. Cleanup
  llamaService.dispose();

  print("\n═══════════════════════════════════════");
  print("✅ Demo completed");
  print("═══════════════════════════════════════");
}
