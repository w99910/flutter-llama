# Function Calling Implementation Summary

## What Was Created

I've implemented a complete function calling system for your Flutter llama.cpp app that automatically detects when to call functions and executes them.

## Key Features

### ✅ Automatic Function Calling

When a user asks "What's 1+1?", the system:

1. Detects the need for a calculation
2. Automatically calls the `calculate` function
3. Gets the result (2)
4. Returns: "1 plus 1 equals 2"

**No manual intervention required!**

### ✅ Built-in Functions

- `calculate` - Math expressions (1+1, sqrt(144), 5^2, etc.)
- `get_current_time` - Current date/time
- `generate_random_number` - Random numbers in range

### ✅ Easy Custom Functions

```dart
executor.registerFunction(
  LlamaFunction(
    name: 'get_weather',
    description: 'Get weather for a city',
    parameters: {...},
  ),
  (name, args) async {
    // Your implementation
    return {'temp': 72, 'condition': 'Sunny'};
  },
);
```

### ✅ Ready-to-Use UI

Complete Flutter chat screen with automatic function calling built-in.

## Files Created

### Core Implementation

1. **`lib/internal/function_calling.dart`**

   - Function definitions (`LlamaFunction`)
   - Parsing utilities
   - Grammar generation
   - Example tools

2. **`lib/internal/auto_function_executor.dart`**
   - Automatic function calling engine
   - Built-in calculator, time, random functions
   - Multi-turn conversation support
   - Custom function registration

### Examples & UI

3. **`lib/screens/auto_function_chat_screen.dart`**

   - Complete Flutter chat UI
   - Streaming responses
   - Function call indicators
   - Ready to use!

4. **`lib/examples/auto_function_demo.dart`**

   - Command-line demo
   - Shows various test cases

5. **`lib/examples/function_calling_example.dart`**

   - Manual implementation examples
   - Advanced use cases

6. **`lib/examples/quick_integration_guide.dart`**
   - How to add to existing chat
   - Real-world examples

### Documentation

7. **`FUNCTION_CALLING_GUIDE.md`**
   - Complete guide
   - API reference
   - Troubleshooting
   - Best practices

### Modified Files

8. **`lib/internal/llama_service.dart`**
   - Added `runPromptWithFunctions()` method
   - Grammar-constrained generation support

## Quick Start

### Simplest Usage (3 lines!)

```dart
final llamaService = LlamaService();
llamaService.loadModel('/path/to/model.gguf');

final executor = AutoFunctionExecutor(llamaService);

// That's it! Now use it:
await executor.processUserInput(
  "What's 1+1?",
  (token) => print(token), // Streams: "1 plus 1 equals 2"
);
```

### Add to Flutter App

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => AutoFunctionChatScreen(
      llamaService: yourLlamaService,
    ),
  ),
);
```

### Add Custom Function

```dart
executor.registerFunction(
  LlamaFunction(
    name: 'my_function',
    description: 'What it does',
    parameters: {
      'type': 'object',
      'properties': {
        'param': {'type': 'string'}
      },
      'required': ['param'],
    },
  ),
  (name, args) async {
    // Your code here
    return {'result': 'success'};
  },
);
```

## How It Works

### Architecture

```
User Input: "What's 1+1?"
     ↓
System Prompt: "You have these tools: calculate, get_time, random..."
     ↓
Model Decides: "I need to call calculate(expression: '1+1')"
     ↓
Grammar Constraint: Ensures valid JSON output
     ↓
Parse: {"name": "calculate", "arguments": {"expression": "1+1"}}
     ↓
Execute Function: calculate("1+1") → returns 2
     ↓
Feed Back to Model: "Function calculate returned 2"
     ↓
Model Responds: "1 plus 1 equals 2"
```

### Key Components

1. **LlamaFunction** - Defines available functions
2. **Grammar Constraint** - Forces valid JSON (via `llama_sampler_init_grammar`)
3. **Auto Loop** - Handles function calling cycle automatically
4. **Result Feeding** - Feeds function results back to model

## Usage Examples

### Example 1: Math

```
User: "What's 25 * 48 + 120?"
→ Calls: calculate("25*48+120")
→ Returns: "The answer is 1,320"
```

### Example 2: Time

```
User: "What time is it?"
→ Calls: get_current_time()
→ Returns: "It's currently 2:30 PM"
```

### Example 3: Multi-turn

```
User: "Calculate 5 * 5"
→ Calls: calculate("5*5")
→ Returns: "5 times 5 equals 25"

User: "Now multiply that by 2"
→ Calls: calculate("25*2")
→ Returns: "25 times 2 equals 50"
```

### Example 4: Custom Function

```dart
// Register weather function
executor.registerFunction(weatherTool, myWeatherHandler);

User: "What's the weather in London?"
→ Calls: get_weather(location: "London")
→ Returns: "It's 72°F and sunny in London"
```

## Best Practices

### ✅ DO:

- Use grammar constraint (`useGrammar: true`)
- Keep temperature low (0.3-0.7)
- Clear function descriptions
- Validate all inputs
- Limit max function calls (prevent loops)

### ❌ DON'T:

- Use high temperature (breaks JSON)
- Vague function descriptions
- Skip input validation
- Allow unlimited function calls
- Use untrained models

## Model Requirements

### Recommended Models

- ✅ Llama 3.1/3.3 (70B best, 8B okay)
- ✅ Functionary v3.1/v3.2
- ✅ Hermes 2/3 Pro
- ✅ Qwen 2.5 series
- ✅ Mistral Nemo

### Generic Models

- ⚠️ Work but require grammar constraint
- ⚠️ May be less reliable

## Testing

Run the demo:

```dart
// Update model path in auto_function_demo.dart
dart run lib/examples/auto_function_demo.dart
```

Test cases included:

- Basic math (1+1)
- Complex expressions (25 \* 48 + 120)
- Square roots (sqrt(144))
- Current time
- Random numbers
- Multi-turn conversations

## API Reference

### AutoFunctionExecutor

```dart
// Initialize
final executor = AutoFunctionExecutor(llamaService);

// Process input (main method)
await executor.processUserInput(
  userInput,
  onToken,
  conversationHistory: [...],
  maxFunctionCalls: 5,
  verbose: true,
);

// Register custom function
executor.registerFunction(function, handler);

// Query available functions
executor.getAvailableFunctions();
executor.getFunction('name');
```

### LlamaService

```dart
// New method: Function calling with grammar
await llamaService.runPromptWithFunctions(
  prompt,
  functions,
  onToken,
  useGrammar: true,
  temperature: 0.7,
  maxTokens: 512,
);
```

## Troubleshooting

### Model doesn't call functions

- ✅ Enable grammar: `useGrammar: true`
- ✅ Lower temperature: `temperature: 0.3`
- ✅ Use function-calling trained model

### Invalid JSON

- ✅ Enable grammar (critical!)
- ✅ Lower temperature
- ✅ Simplify function schemas

### Wrong function called

- ✅ Improve function descriptions
- ✅ Add more detail to parameters

### Infinite loops

- ✅ Set `maxFunctionCalls: 3`

## Performance

- **Small models (8B)**: 5-15 tokens/sec
- **Large models (70B)**: 1-5 tokens/sec
- **With GPU**: 10-30 tokens/sec

Function calling adds ~50-200 tokens per function definition to context.

## Security

⚠️ **Always validate inputs!**

```dart
executor.registerFunction(
  myFunction,
  (name, args) async {
    // Validate
    if (args['path']?.contains('..')) {
      throw Exception('Invalid path');
    }

    // Sanitize
    final amount = (args['amount'] as num).toDouble();
    if (amount < 0 || amount > 1000) {
      throw Exception('Out of range');
    }

    // Execute safely
    return await secureImplementation(args);
  },
);
```

## Next Steps

1. **Test it out**: Run `auto_function_demo.dart`
2. **Try the UI**: Use `AutoFunctionChatScreen`
3. **Add custom functions**: Register your own tools
4. **Read the guide**: See `FUNCTION_CALLING_GUIDE.md`
5. **Integrate**: Follow `quick_integration_guide.dart`

## Support

Check these files for help:

- `FUNCTION_CALLING_GUIDE.md` - Complete guide
- `lib/examples/auto_function_demo.dart` - Working examples
- `lib/examples/quick_integration_guide.dart` - Integration tips

## Credits

Based on:

- [llama.cpp function calling](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md)
- [OpenAI function calling API](https://platform.openai.com/docs/guides/function-calling)
