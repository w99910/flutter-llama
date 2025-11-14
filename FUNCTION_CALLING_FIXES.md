# Function Calling Not Working? Quick Fixes

## Problem: Model outputs `<think>` tags or reasoning instead of calling functions

### Example of the Issue:

```
Input: "What's 1+1?"
Output: "<think>Okay, the user is asking what 1 plus 1 equals..."
Expected: {"name": "calculate", "arguments": {"expression": "1+1"}}
```

## Root Causes

### 1. **Reasoning Model** (Most Common)

You're using a reasoning model like:

- DeepSeek R1
- QwQ models
- Models with "reasoning" or "o1" in the name

**Solution:** Use a non-reasoning model OR apply the patches below.

### 2. **Temperature Too High**

Temperature > 0.5 can cause the model to ignore constraints.

**Solution:** Lower temperature to 0.1-0.3

### 3. **Grammar Not Working**

Grammar constraint may not be properly applied.

**Solution:** Verify grammar sampler initialization

## Quick Fixes

### Fix 1: Lower Temperature (Try This First!)

```dart
await executor.processUserInput(
  userInput,
  onToken,
  // Change from default 0.7 to 0.3 or lower
);
```

The code has been updated to use `temperature: 0.3` by default now.

### Fix 2: Use Recommended Models

**✅ Models that work well:**

- Llama 3.1 / 3.3 (8B or 70B)
- Functionary v3.1 / v3.2
- Hermes 2 Pro / Hermes 3
- Qwen 2.5 (7B or larger)
- Mistral Nemo

**❌ Avoid these models:**

- DeepSeek R1 (reasoning model)
- QwQ models (reasoning)
- Base models (not instruction-tuned)
- Models with "o1" or "reasoning" in name

### Fix 3: Manual Cleaning (If Stuck with Reasoning Model)

The `AutoFunctionExecutor` now automatically cleans `<think>` tags, but if you still have issues:

```dart
// The cleaner now strips:
// 1. <think>...</think> tags and content
// 2. Markdown code blocks
// 3. Extracts JSON from surrounding text
```

### Fix 4: Stronger System Prompt

The system prompt has been updated to be more explicit:

```
CRITICAL INSTRUCTIONS:
1. When you need to use a tool, you MUST respond with ONLY a JSON object
2. DO NOT include any other text, explanations, or thoughts.
3. DO NOT use <think> tags or reasoning steps.
4. DO NOT explain your reasoning.
5. Just output the JSON object directly.
```

### Fix 5: Test Your Model

Run the troubleshooter to diagnose issues:

```dart
import 'package:flutter_application_1/tools/function_calling_troubleshooter.dart';

void main() async {
  final llamaService = LlamaService();
  llamaService.loadModel('/path/to/model.gguf');

  final troubleshooter = FunctionCallingTroubleshooter(llamaService);
  await troubleshooter.diagnose();

  llamaService.dispose();
}
```

This will tell you:

- If your model can generate JSON
- If grammar constraint is working
- If the model follows instructions
- Specific recommendations for your model

## What Changed in the Code

### 1. Auto Function Executor

- ✅ Temperature lowered to 0.3 (from 0.7)
- ✅ Added `_cleanModelOutput()` to strip `<think>` tags
- ✅ Better JSON extraction from text

### 2. System Prompt

- ✅ More explicit "DO NOT" instructions
- ✅ Emphasis on "ONLY JSON"
- ✅ Example showing correct format

### 3. Output Cleaning

Now automatically removes:

- `<think>...</think>` tags
- Markdown code blocks (```json)
- Surrounding explanatory text

## Testing

### Test 1: Simple calculation

```dart
await executor.processUserInput(
  "What's 1+1?",
  (token) => print(token),
);
```

Expected: Function call → "1 plus 1 equals 2"

### Test 2: With verbose logging

```dart
await executor.processUserInput(
  "Calculate 5*5",
  (token) => print(token),
  verbose: true, // See what's happening
);
```

Check the logs for:

- "📥 Model output:" - Raw model response
- "🧹 Cleaned output:" - After removing reasoning
- "🔧 Detected function call" - Successful parsing

### Test 3: Run full diagnostics

```bash
dart run lib/tools/function_calling_troubleshooter.dart
```

## Still Not Working?

### Debug Checklist:

1. **Check model output:**

   ```dart
   verbose: true  // Enable in processUserInput
   ```

   Look for `<think>` tags in the output

2. **Try extreme low temperature:**

   ```dart
   temperature: 0.1  // Almost deterministic
   ```

3. **Verify grammar is enabled:**

   ```dart
   useGrammar: true  // Should be default
   ```

4. **Check model:**

   - Is it instruction-tuned?
   - Does it support chat format?
   - Is it a reasoning model?

5. **Test without function calling:**
   ```dart
   await llamaService.runPromptStreaming(
     "Say the word 'test'",
     (token) => print(token),
   );
   ```
   If this doesn't work, your model/setup has basic issues.

## Model-Specific Solutions

### DeepSeek R1 / Reasoning Models

```dart
// These models ALWAYS output <think> tags
// The auto cleaner should handle it, but if not:

// Option 1: Strip manually
String cleanOutput(String text) {
  return text.replaceAll(
    RegExp(r'<think>.*?</think>', dotAll: true),
    '',
  ).trim();
}

// Option 2: Use a different model (recommended)
```

### Generic Instruction Models

```dart
// For models without native function calling:
// 1. Use temperature: 0.1-0.3
// 2. Enable grammar: true
// 3. Keep system prompt explicit
```

### Llama 3.1+ (Native Support)

```dart
// These should work out of the box
// If not:
// 1. Verify chat template is correct
// 2. Check model is actually Llama 3.1+
// 3. Use official GGUF files
```

## Performance Tips

1. **Lower temperature** = More reliable but less creative

   - Function calling: 0.1-0.3
   - Normal chat: 0.7-0.8

2. **Grammar constraint** = Slower but reliable

   - Always enable for function calling
   - Adds ~10-20% overhead

3. **Max tokens** = Balance accuracy and speed
   - Function calls need ~50-100 tokens
   - Final response needs 100-500 tokens
   - Default 512 is good

## Get Help

If nothing works:

1. Run the troubleshooter
2. Share the diagnostic output
3. Include:
   - Model name
   - Temperature setting
   - Raw model output (with verbose: true)
   - Whether grammar is enabled

## Summary

**The main fix:** Your model is probably outputting reasoning/thinking text instead of JSON. The code has been updated to:

1. ✅ Use lower temperature (0.3)
2. ✅ Stronger system prompt
3. ✅ Automatic `<think>` tag removal
4. ✅ Better JSON extraction

**If it still doesn't work:** Use a recommended function-calling model like Llama 3.1, Functionary, or Hermes 2 Pro.
