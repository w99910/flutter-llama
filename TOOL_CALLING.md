# Tool Calling with Qwen3 0.6B

This implementation adds function/tool calling capabilities to the Flutter LLaMA chat app, specifically designed for Qwen3 0.6B which supports tool calling natively.

## Overview

The tool calling system allows the model to:
- Detect when a function needs to be called
- Parse function call requests with arguments
- Execute the function
- Receive the result and continue the conversation

## Features

### Built-in Tools

The following mathematical functions are available by default:

1. **add(a, b)** - Add two numbers
2. **subtract(a, b)** - Subtract b from a
3. **multiply(a, b)** - Multiply two numbers
4. **divide(a, b)** - Divide a by b

### Example Usage

**User:** "What is 1+1?"

The model will:
1. Recognize this requires the `add` function
2. Call `add(1, 1)`
3. Receive the result: `2`
4. Respond: "1 + 1 equals 2"

## Architecture

### Core Components

1. **tool_calling.dart** - Core tool calling infrastructure
   - `FunctionTool` - Represents a callable function with schema
   - `FunctionParameter` - Defines function parameters
   - `ToolRegistry` - Manages available tools
   - `ToolCallParser` - Parses tool calls from model output
   - Helper functions for formatting

2. **built_in_tools.dart** - Built-in mathematical functions
   - Creates default tool registry with math operations

3. **llama_service.dart** - Extended with `runPromptWithTools`
   - Handles multi-turn tool calling
   - Executes tools and feeds results back
   - Supports up to 5 tool calls per conversation turn

4. **Integration**
   - `llama_isolate.dart` - Routes tool calls through isolate
   - `llama_request.dart` - Extended to pass tool registry
   - `lcontroller.dart` - Exposes tool calling to UI
   - `main.dart` - UI toggle and prompt formatting

## How It Works

### 1. Smart Detection

The system uses a two-layer approach to prevent unnecessary tool calls:

**Layer 1: Message Analysis**
- Checks if the user message contains calculation-related keywords
- Looks for math operators (+, -, *, /, ×, ÷)
- Verifies presence of numbers
- Only includes tool definitions if message seems calculation-related

**Layer 2: Model Instructions**
- Clear instructions to use tools ONLY when specifically needed
- Explicit guidance to answer general questions directly
- Examples of when NOT to use tools

This prevents the model from trying to use tools for unrelated questions like "What is Bitcoin?"

### 2. Tool Definition Format (Qwen3)

Tools are defined in JSON schema format and included in the system prompt:

```json
[
  {
    "type": "function",
    "function": {
      "name": "add",
      "description": "Add two numbers together",
      "parameters": {
        "type": "object",
        "properties": {
          "a": {"type": "number", "description": "First number"},
          "b": {"type": "number", "description": "Second number"}
        },
        "required": ["a", "b"]
      }
    }
  }
]
```

### 2. Tool Call Format (Model Output)

When the model wants to call a tool, it generates:

```xml
<tool_call>
{"name": "add", "arguments": {"a": 1, "b": 1}}
</tool_call>
```

### 3. Tool Result Format (System Response)

Results are fed back to the model:

```xml
<tool_response>
{"name": "add", "result": 2}
</tool_response>
```

### 4. Multi-Turn Flow

```
User: "What is 1+1?"
  ↓
Model: <tool_call>{"name": "add", "arguments": {"a": 1, "b": 1}}</tool_call>
  ↓
System: Executes add(1, 1) = 2
  ↓
System: <tool_response>{"name": "add", "result": 2}</tool_response>
  ↓
Model: "The answer is 2"
  ↓
User sees: "The answer is 2"
```

## Usage

### Enable/Disable Tool Calling

1. Open the app
2. Tap the Settings icon (⚙️)
3. Toggle "Enable Tool Calling"

When enabled, the model will automatically detect when to use tools.

### Test Examples

Try these prompts with tool calling enabled:

- "What is 1+1?"
- "Calculate 25 * 4"
- "What's 100 divided by 5?"
- "What is (3 + 7) * 2?" (Tests multiple tool calls)

## Adding Custom Tools

### Step 1: Define Your Tool

```dart
registry.register(
  FunctionTool(
    name: 'get_weather',
    description: 'Get current weather for a location',
    parameters: [
      FunctionParameter(
        name: 'location',
        type: 'string',
        description: 'City name',
        required: true,
      ),
      FunctionParameter(
        name: 'unit',
        type: 'string',
        description: 'Temperature unit (celsius/fahrenheit)',
        required: false,
      ),
    ],
    execute: (arguments) {
      final location = arguments['location'] as String;
      final unit = arguments['unit'] as String? ?? 'celsius';
      // Your implementation here
      return {
        'temperature': 22,
        'condition': 'sunny',
        'unit': unit,
      };
    },
  ),
);
```

### Step 2: Register in built_in_tools.dart

Add your tool to the `createBuiltInTools()` function:

```dart
ToolRegistry createBuiltInTools() {
  final registry = ToolRegistry();
  
  // Existing tools...
  registry.register(/* add tool */);
  
  // Your new tool
  registry.register(/* your tool */);
  
  return registry;
}
```

### Step 3: Test

The model will automatically detect when your tool is needed based on the description.

## Technical Details

### Thread Safety

- Tool registry is passed through isolate boundaries
- Tools are executed in the isolate thread
- Results are streamed back to UI thread safely

### Performance

- Tool parsing uses efficient regex matching
- Minimal overhead when tool calling is disabled
- Tools execute synchronously (consider async if needed)

### Limitations

- Maximum 5 tool calls per turn (configurable)
- Tools must be synchronous (can be extended for async)
- No nested tool calls (sequential only)
- Model must be Qwen3 or compatible with `<tool_call>` format

## Troubleshooting

### Model doesn't call tools

1. Ensure "Enable Tool Calling" is ON in settings
2. Check that you're using Qwen3 0.6B model
3. Try explicit prompts: "Use the add function to calculate 1+1"

### Tool parsing errors

Check console output for:
- `🔧 Tool call detected` - Tool call recognized
- `Executing tool: ...` - Tool being executed
- `Tool result: ...` - Execution result

### Tool execution errors

- Verify parameter types match expectations
- Check for division by zero or invalid operations
- Review console logs for exception messages

## Model Compatibility

This implementation is designed for **Qwen3 0.6B** which natively supports:
- `<tool_call>` / `</tool_call>` tags
- JSON-formatted function calls
- Tool schemas in system prompts

Other models may require adaptation of:
- Tag formats (e.g., `[TOOL_CALL]`, `###TOOL###`)
- JSON parsing (some use different formats)
- Prompt engineering (different instruction styles)

## Future Enhancements

Potential improvements:

- [ ] Async tool support
- [ ] Tool call history/logging
- [ ] Custom tool UI builder
- [ ] Tool call confirmation prompts
- [ ] Parallel tool execution
- [ ] Tool call visualization
- [ ] Export/import tool definitions

## References

- [Qwen3 Documentation](https://github.com/QwenLM/Qwen)
- [Function Calling Best Practices](https://platform.openai.com/docs/guides/function-calling)
- [llama.cpp Tool Calling](https://github.com/ggerganov/llama.cpp/discussions/3536)
