# Function Calling Guide

Complete guide to implementing function calling with llama.cpp in Flutter.

## Overview

Function calling allows your LLM to automatically invoke functions/tools when needed. For example:

- User asks "What's 1+1?" → Model calls `calculate("1+1")` → Returns `2`
- User asks "What time is it?" → Model calls `get_current_time()` → Returns current time

## Quick Start

### 1. Automatic Function Calling (Recommended)

Use `AutoFunctionExecutor` for the simplest experience - it handles everything automatically:

```dart
import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/internal/auto_function_executor.dart';

// Initialize
final llamaService = LlamaService();
llamaService.loadModel('/path/to/model.gguf');

final executor = AutoFunctionExecutor(llamaService);

// Use it
await executor.processUserInput(
  "What's 1+1?",
  (token) => print(token), // Streams response
);
// Output: "1 + 1 equals 2"
```

**Built-in functions:**

- `calculate` - Math expressions (e.g., "1+1", "sqrt(144)", "5^2")
- `get_current_time` - Current date/time
- `generate_random_number` - Random number in range

### 2. Add Custom Functions

```dart
final executor = AutoFunctionExecutor(llamaService);

// Register a custom function
executor.registerFunction(
  LlamaFunction(
    name: 'get_weather',
    description: 'Get current weather for a location',
    parameters: {
      'type': 'object',
      'properties': {
        'location': {
          'type': 'string',
          'description': 'City name',
        }
      },
      'required': ['location'],
    },
  ),
  (functionName, arguments) async {
    final location = arguments['location'];
    // Call your weather API here
    return {
      'temperature': 72,
      'condition': 'Sunny',
      'location': location,
    };
  },
);

// Now the model can call it
await executor.processUserInput(
  "What's the weather in London?",
  (token) => print(token),
);
```

### 3. Use in Flutter UI

```dart
import 'package:flutter_application_1/screens/auto_function_chat_screen.dart';

// In your widget tree
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => AutoFunctionChatScreen(
      llamaService: yourLlamaService,
    ),
  ),
);
```

This provides a complete chat interface with automatic function calling.

## Architecture

### How It Works

1. **User Input** → "What's 1+1?"

2. **System Prompt** → Model receives:

   ```
   You have access to these tools:
   - calculate(expression: string)
   - get_current_time()
   ...
   When you need a tool, respond with:
   {"name": "function_name", "arguments": {...}}
   ```

3. **Model Decides** → Outputs:

   ```json
   { "name": "calculate", "arguments": { "expression": "1+1" } }
   ```

4. **Grammar Constraint** → Ensures valid JSON (via `llama_sampler_init_grammar`)

5. **Execute Function** → Calls `calculate("1+1")` → Returns `2`

6. **Feed Back** → Model receives result and generates:
   ```
   "1 plus 1 equals 2"
   ```

### Components

#### 1. `function_calling.dart` - Core Types

```dart
// Define a function
final weatherTool = LlamaFunction(
  name: 'get_weather',
  description: 'Get weather for a location',
  parameters: {...}, // JSON Schema
);

// Parse function calls from model output
final calls = FunctionCallingHelper.parseFunctionCalls(modelOutput);

// Create grammar for constrained generation
final grammar = FunctionCallingHelper.createFunctionCallGrammar(functions);
```

#### 2. `llama_service.dart` - Low-level API

```dart
// Call with grammar constraint
await llamaService.runPromptWithFunctions(
  prompt,
  functions,
  onToken,
  useGrammar: true, // Forces valid JSON
);
```

#### 3. `auto_function_executor.dart` - High-level API

```dart
// Handles entire loop automatically
await executor.processUserInput(
  userInput,
  onToken,
  maxFunctionCalls: 5, // Prevent loops
);
```

## Advanced Usage

### Manual Function Calling

If you need more control:

```dart
import 'package:flutter_application_1/internal/function_calling.dart';

// Define functions
final functions = [
  LlamaFunction(
    name: 'calculate',
    description: 'Evaluate math expressions',
    parameters: {
      'type': 'object',
      'properties': {
        'expression': {'type': 'string'}
      },
      'required': ['expression'],
    },
  ),
];

// Build prompt with tools
final systemPrompt = FunctionCallingHelper.formatToolsSystemPrompt(functions);
final prompt = '<|im_start|>system\n$systemPrompt<|im_end|>\n'
                '<|im_start|>user\nWhat is 5+3?<|im_end|>\n'
                '<|im_start|>assistant\n';

// Generate with grammar
final output = await llamaService.runPromptWithFunctions(
  prompt,
  functions,
  (token) => print(token),
  useGrammar: true,
);

// Parse function call
final calls = FunctionCallingHelper.parseFunctionCalls(output);

if (calls != null) {
  for (final call in calls) {
    print('Function: ${call.name}');
    print('Arguments: ${call.arguments}');

    // Execute it
    final result = myExecute(call.name, call.arguments);

    // Feed result back to model
    final followUp = FunctionCallingHelper.formatFunctionResult(
      call.name,
      result,
    );
    // Continue conversation with result...
  }
}
```

### Multi-turn Conversations

```dart
final conversationHistory = <Map<String, String>>[];

// Turn 1
await executor.processUserInput(
  "Calculate 5 * 5",
  (token) => print(token),
  conversationHistory: conversationHistory,
);
// Model calls calculate(5*5) → returns 25 → "5 times 5 equals 25"

// Turn 2 (model remembers context)
await executor.processUserInput(
  "Now add 10 to that",
  (token) => print(token),
  conversationHistory: conversationHistory,
);
// Model calls calculate(25+10) → returns 35 → "Adding 10 gives you 35"
```

## Model Requirements

### Best Models for Function Calling

**Native Support** (recommended):

- ✅ Llama 3.1/3.3 (70B best, 8B okay)
- ✅ Functionary v3.1/v3.2
- ✅ Hermes 2/3 Pro
- ✅ Qwen 2.5 series
- ✅ Mistral Nemo

**Generic Support** (works but slower):

- ⚠️ Most instruction-tuned models
- Use with grammar constraint for best results

### Model Setup

```dart
// For native function calling models, use appropriate chat template
llamaService.loadModel(
  '/path/to/llama-3.3-70b.gguf',
);

// For generic models, rely on system prompt + grammar
llamaService.loadModel(
  '/path/to/generic-model.gguf',
);
```

## Parameters

### Temperature

```dart
await executor.processUserInput(
  userInput,
  onToken,
  temperature: 0.3, // Lower = more reliable function calls
);
```

- **0.1-0.4** - Reliable function calling, deterministic
- **0.5-0.7** - Balanced (default)
- **0.8+** - Creative but may break JSON format

### Max Function Calls

```dart
await executor.processUserInput(
  userInput,
  onToken,
  maxFunctionCalls: 3, // Limit recursive calls
);
```

Prevents infinite loops if model keeps calling functions.

### Grammar Constraint

```dart
await llamaService.runPromptWithFunctions(
  prompt,
  functions,
  onToken,
  useGrammar: true, // ← Ensures valid JSON
);
```

**When to use:**

- ✅ Always (recommended)
- ✅ Essential for generic models
- ✅ Improves reliability for all models

**When to disable:**

- ⚠️ Native models with excellent function calling (rare)
- ⚠️ You want natural language mixed with function calls

## Troubleshooting

### Model doesn't call functions

**Cause:** Model doesn't understand function calling format

**Fix:**

1. Use a function-calling trained model
2. Enable grammar constraint: `useGrammar: true`
3. Lower temperature: `temperature: 0.3`
4. Make function descriptions clearer

### Invalid JSON output

**Cause:** Model generates malformed JSON

**Fix:**

1. Enable grammar: `useGrammar: true` (critical!)
2. Lower temperature
3. Use smaller, focused function schemas

### Wrong function called

**Cause:** Ambiguous function descriptions

**Fix:**

```dart
// Bad
LlamaFunction(
  name: 'get_data',
  description: 'Gets data', // Too vague!
  ...
)

// Good
LlamaFunction(
  name: 'get_weather',
  description: 'Get current weather conditions for a specific city or location',
  ...
)
```

### Infinite function calls

**Cause:** Model stuck in loop

**Fix:**

```dart
await executor.processUserInput(
  userInput,
  onToken,
  maxFunctionCalls: 3, // Limit iterations
);
```

### Slow performance

**Cause:** Function definitions use too many tokens

**Fix:**

- Reduce number of functions (pass only relevant ones)
- Simplify parameter schemas
- Use smaller models (8B instead of 70B)

## Examples

See these files for complete examples:

- **`lib/examples/auto_function_demo.dart`** - Command-line demo
- **`lib/examples/function_calling_example.dart`** - Manual implementation
- **`lib/screens/auto_function_chat_screen.dart`** - Flutter UI

## API Reference

### AutoFunctionExecutor

```dart
final executor = AutoFunctionExecutor(llamaService);

// Register function
executor.registerFunction(
  LlamaFunction(...),
  (name, args) async => {...},
);

// Process input
await executor.processUserInput(
  userInput,
  onToken,
  conversationHistory: [...],
  maxFunctionCalls: 5,
  verbose: true,
);

// Get available functions
final functions = executor.getAvailableFunctions();
final details = executor.getFunction('calculate');
```

### LlamaFunction

```dart
final func = LlamaFunction(
  name: 'function_name',
  description: 'What it does',
  parameters: {
    'type': 'object',
    'properties': {
      'param': {
        'type': 'string',
        'description': 'Parameter description',
      }
    },
    'required': ['param'],
  },
);
```

### FunctionCall

```dart
final call = FunctionCall(
  name: 'calculate',
  arguments: {'expression': '1+1'},
);

final json = call.toJson();
```

## Performance Tips

1. **Use quantized models** - Q4_K_M or Q5_K_M for speed
2. **Limit context** - Only include recent conversation history
3. **Batch functions** - Register all at once, not one-by-one
4. **Cache prompts** - Reuse system prompts when possible
5. **GPU acceleration** - Essential for 70B+ models

## Security

⚠️ **Important:** Always validate and sanitize function arguments!

```dart
executor.registerFunction(
  myFunction,
  (name, args) async {
    // Validate
    if (args['file_path']?.contains('..')) {
      throw Exception('Invalid path');
    }

    // Sanitize
    final amount = (args['amount'] as num).toDouble();
    if (amount < 0 || amount > 1000) {
      throw Exception('Amount out of range');
    }

    // Execute safely
    return await mySecureImplementation(args);
  },
);
```

## Further Reading

- [llama.cpp function calling docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md)
- [OpenAI function calling guide](https://platform.openai.com/docs/guides/function-calling)
- [GBNF grammar syntax](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md)

## Support

Issues? Check:

1. Model supports function calling
2. Grammar constraint enabled
3. Temperature not too high
4. Function descriptions are clear
5. Check logs with `verbose: true`
