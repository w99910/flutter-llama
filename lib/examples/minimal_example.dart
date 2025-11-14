import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/internal/auto_function_executor.dart';

/// MINIMAL WORKING EXAMPLE
/// Copy-paste this to test function calling in 5 minutes!

void main() async {
  print("🤖 Minimal Function Calling Example\n");

  // 1. Initialize service
  final llamaService = LlamaService();

  // 2. Load model (CHANGE THIS PATH!)
  print("Loading model...");
  final success = llamaService.loadModel(
    '/path/to/your/model.gguf', // ← CHANGE THIS
  );

  if (!success) {
    print("❌ Failed to load model. Check the path!");
    return;
  }

  print("✅ Model loaded\n");

  // 3. Create executor (includes built-in math, time, random functions)
  final executor = AutoFunctionExecutor(llamaService);

  // 4. Test it!
  print("Testing: 'What's 1+1?'\n");
  print("Response: ");

  await executor.processUserInput(
    "What's 1+1?",
    (token) => print(token), // Prints response as it streams
  );

  print("\n\n✅ Done!");

  // 5. Cleanup
  llamaService.dispose();
}

/// Expected output:
/// ```
/// 🤖 Minimal Function Calling Example
///
/// Loading model...
/// ✅ Model loaded
///
/// Testing: 'What's 1+1?'
///
/// Response:
/// 🔧 Detected 1 function call(s)
///   📞 Calling: calculate
///   📋 Arguments: {"expression":"1+1"}
///   ✅ Result: {"expression":"1+1","result":2.0,"success":true}
///
/// 1 plus 1 equals 2.
///
/// ✅ Done!
/// ```

/// To run:
/// 1. Update model path above
/// 2. Run: dart run lib/examples/minimal_example.dart
/// 3. Try these queries:
///    - "What's 1+1?"
///    - "Calculate 25 * 48"
///    - "What time is it?"
///    - "Pick a random number between 1 and 100"
