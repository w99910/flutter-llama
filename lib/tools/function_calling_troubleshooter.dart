import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/internal/auto_function_executor.dart';

/// Troubleshooting helper for function calling issues
///
/// Run this to diagnose why your model isn't calling functions properly
class FunctionCallingTroubleshooter {
  final LlamaService llamaService;

  FunctionCallingTroubleshooter(this.llamaService);

  /// Run diagnostics to identify issues
  Future<void> diagnose() async {
    print("\n" + "═" * 50);
    print("🔍 FUNCTION CALLING DIAGNOSTICS");
    print("═" * 50 + "\n");

    // Test 1: Check if model can generate JSON
    await _testJsonGeneration();

    // Test 2: Check if grammar constraint works
    await _testGrammarConstraint();

    // Test 3: Check if model follows instructions
    await _testInstructionFollowing();

    // Test 4: Test with AutoFunctionExecutor
    await _testAutoExecutor();

    print("\n" + "═" * 50);
    print("📊 DIAGNOSTIC SUMMARY");
    print("═" * 50 + "\n");

    _printRecommendations();
  }

  /// Test 1: Basic JSON generation
  Future<void> _testJsonGeneration() async {
    print("Test 1: Basic JSON Generation");
    print("-" * 50);

    final prompt = '''<|im_start|>system
You are a JSON generator. Only output valid JSON.
<|im_end|>
<|im_start|>user
Generate a JSON object with name "test" and value 123
<|im_end|>
<|im_start|>assistant
''';

    final buffer = StringBuffer();
    await llamaService.runPromptStreaming(
      prompt,
      (token) => buffer.write(token),
      temperature: 0.3,
      maxTokens: 100,
    );

    final output = buffer.toString().trim();
    print("Output: $output\n");

    if (output.contains('<think>') || output.contains('reasoning')) {
      print("❌ ISSUE: Model outputs reasoning/thinking");
      print("   This is a reasoning model (like DeepSeek R1)");
      print("   Solutions:");
      print("   - Use a non-reasoning model");
      print("   - Or add special handling to strip <think> tags\n");
    } else if (output.startsWith('{') && output.contains('"name"')) {
      print("✅ Model can generate JSON\n");
    } else {
      print("⚠️  Model output is not valid JSON");
      print("   This model may not be suitable for function calling\n");
    }
  }

  /// Test 2: Grammar-constrained generation
  Future<void> _testGrammarConstraint() async {
    print("Test 2: Grammar-Constrained JSON");
    print("-" * 50);

    final prompt = '''<|im_start|>system
Generate a function call.
<|im_end|>
<|im_start|>user
Call the calculate function with expression "1+1"
<|im_end|>
<|im_start|>assistant
''';

    final executor = AutoFunctionExecutor(llamaService);
    final functions = [executor.getFunction('calculate')!];

    final buffer = StringBuffer();

    try {
      await llamaService.runPromptWithFunctions(
        prompt,
        functions,
        (token) => buffer.write(token),
        useGrammar: true,
        temperature: 0.3,
        maxTokens: 100,
      );

      final output = buffer.toString().trim();
      print("Output: $output\n");

      if (output.contains('<think>')) {
        print("❌ ISSUE: Grammar constraint not preventing reasoning");
        print("   The grammar may not be working properly");
        print("   Solutions:");
        print("   - Try temperature: 0.1 (very low)");
        print("   - Use a model trained for function calling");
        print("   - Manually strip reasoning tags\n");
      } else if (output.startsWith('{') && output.contains('"name"')) {
        print("✅ Grammar constraint is working\n");
      } else {
        print("⚠️  Grammar constraint produced unexpected output\n");
      }
    } catch (e) {
      print("❌ ERROR: Grammar sampler failed");
      print("   $e");
      print("   This might indicate a library compilation issue\n");
    }
  }

  /// Test 3: Instruction following
  Future<void> _testInstructionFollowing() async {
    print("Test 3: Instruction Following");
    print("-" * 50);

    final prompt = '''<|im_start|>system
You are a helpful assistant. When asked to calculate, respond with ONLY this JSON format:
{"name": "calculate", "arguments": {"expression": "the expression"}}
Do NOT include any other text or explanations.
<|im_end|>
<|im_start|>user
What's 1+1?
<|im_end|>
<|im_start|>assistant
''';

    final buffer = StringBuffer();
    await llamaService.runPromptStreaming(
      prompt,
      (token) => buffer.write(token),
      temperature: 0.3,
      maxTokens: 200,
    );

    final output = buffer.toString().trim();
    print("Output: $output\n");

    if (output.contains('"name"') && output.contains('"calculate"')) {
      print("✅ Model follows instructions\n");
    } else if (output.contains('plus') || output.contains('equals')) {
      print("⚠️  Model responded conversationally instead of calling function");
      print("   Solutions:");
      print("   - Use a function-calling trained model");
      print("   - Enable grammar constraint");
      print("   - Use lower temperature (0.1-0.3)\n");
    } else if (output.contains('<think>')) {
      print("❌ Model is outputting reasoning");
      print("   This is a reasoning model - not ideal for function calling\n");
    } else {
      print("⚠️  Unexpected output format\n");
    }
  }

  /// Test 4: Full auto executor test
  Future<void> _testAutoExecutor() async {
    print("Test 4: AutoFunctionExecutor Integration");
    print("-" * 50);

    final executor = AutoFunctionExecutor(llamaService);
    final buffer = StringBuffer();

    try {
      await executor.processUserInput(
        "What's 1+1?",
        (token) => buffer.write(token),
        verbose: false,
      );

      final output = buffer.toString();
      print("Output: $output\n");

      if (output.contains('2') || output.contains('two')) {
        print("✅ Auto executor working correctly!\n");
      } else if (output.contains('<think>')) {
        print("❌ Auto executor receiving reasoning output");
        print("   The output cleaning didn't help");
        print("   Recommendation: Use a different model\n");
      } else {
        print("⚠️  Auto executor produced unexpected output\n");
      }
    } catch (e) {
      print("❌ ERROR: $e\n");
    }
  }

  /// Print recommendations based on common issues
  void _printRecommendations() {
    print("💡 RECOMMENDATIONS:\n");

    print("1. Model Selection:");
    print("   ✅ Best: Llama 3.1/3.3, Functionary, Hermes, Qwen 2.5");
    print("   ⚠️  Avoid: Reasoning models (DeepSeek R1, o1-style)");
    print("   ⚠️  Avoid: Base models (not instruction-tuned)\n");

    print("2. Parameters:");
    print("   ✅ temperature: 0.1-0.3 (for reliable function calling)");
    print("   ✅ useGrammar: true (ALWAYS enable)");
    print("   ⚠️  Avoid: temperature > 0.5\n");

    print("3. If using a reasoning model:");
    print("   - Post-process to remove <think> tags");
    print("   - Use very low temperature (0.1)");
    print("   - Or switch to a non-reasoning model\n");

    print("4. System Prompt:");
    print("   ✅ Be explicit: 'Output ONLY JSON, no explanations'");
    print("   ✅ Show examples");
    print("   ✅ Use all caps for critical instructions\n");

    print("5. Debug Steps:");
    print("   1. Check model output with verbose: true");
    print("   2. Verify grammar sampler is initialized");
    print("   3. Test with temperature: 0.1");
    print("   4. Try a known function-calling model");
    print("   5. Check for <think> tags in output\n");
  }
}

/// Quick diagnostic tool - run from command line
void main() async {
  print("Starting Function Calling Diagnostics...\n");

  final llamaService = LlamaService();

  // CHANGE THIS to your model path
  final modelPath = '/path/to/your/model.gguf';

  print("Loading model: $modelPath");
  final success = llamaService.loadModel(modelPath);

  if (!success) {
    print("❌ Failed to load model!");
    return;
  }

  print("✅ Model loaded\n");

  final troubleshooter = FunctionCallingTroubleshooter(llamaService);
  await troubleshooter.diagnose();

  llamaService.dispose();

  print("\nDiagnostics complete!");
}
