# Quick Start: Tool Calling

## What It Does
Qwen3 0.6B can now automatically call functions like `add()`, `subtract()`, `multiply()`, and `divide()` when users ask math questions.

## Try It Now

1. **Launch the app**
   ```bash
   flutter run
   ```

2. **Ask a math question**
   - "What is 1+1?"
   - "Calculate 25 * 4"
   - "What's 100 divided by 5?"

3. **See the magic** ✨
   ```
   You: What is 1+1?
   
   Assistant: [Tool: add({'a': 1, 'b': 1}) = 2]
   The answer is 2.
   ```

## Toggle Tool Calling

Settings (⚙️) → "Enable Tool Calling"
- **ON** (default): Model uses functions
- **OFF**: Normal chat without tools

## Available Functions

| Function | Example |
|----------|---------|
| `add(a, b)` | "What is 5 + 3?" |
| `subtract(a, b)` | "What's 10 minus 4?" |
| `multiply(a, b)` | "Calculate 7 times 8" |
| `divide(a, b)` | "Divide 100 by 5" |

## Add Your Own Tool

Edit `lib/built_in_tools.dart`:

```dart
registry.register(
  FunctionTool(
    name: 'your_tool',
    description: 'What it does',
    parameters: [
      FunctionParameter(
        name: 'param_name',
        type: 'string',  // or 'number'
        description: 'What this param is for',
        required: true,
      ),
    ],
    execute: (arguments) {
      // Your code here
      return 'result';
    },
  ),
);
```

## Test Suite

```bash
flutter test test/tool_calling_test.dart
```

**Result**: ✅ 13/13 tests passing

## Documentation

- **Full Guide**: `TOOL_CALLING.md`
- **Implementation Details**: `IMPLEMENTATION_SUMMARY.md`
- **This File**: Quick reference

## That's It!

You're ready to use tool calling with Qwen3 0.6B. Just ask math questions naturally and watch the model use functions automatically! 🚀
