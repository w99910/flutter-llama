# Tool Calling Flow Diagram

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter UI (main.dart)                  │
│  • User input                                                   │
│  • Tool calling toggle                                          │
│  • Display results                                              │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Controller (lcontroller.dart)                  │
│  • Manages isolate communication                                │
│  • Streams tokens back to UI                                    │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Isolate (llama_isolate.dart)                    │
│  • Runs in background thread                                    │
│  • Routes to service layer                                      │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│              Service (llama_service.dart)                       │
│  • runPromptStreaming() - Normal mode                           │
│  • runPromptWithTools() - Tool calling mode                     │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│            Tool System (tool_calling.dart)                      │
│  • ToolRegistry - Manages tools                                 │
│  • ToolCallParser - Parses model output                         │
│  • FunctionTool - Executes functions                            │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Flow: User Asks "What is 1+1?"

```
┌──────────────┐
│ 1. User Input│
│ "What is 1+1?"│
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 2. Format Prompt                         │
│                                          │
│ System: You have access to these tools: │
│ [{"type": "function", "function": {      │
│   "name": "add",                         │
│   "description": "Add two numbers"...    │
│ }}]                                      │
│                                          │
│ User: What is 1+1?                       │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 3. Model Processes                       │
│                                          │
│ Qwen3 0.6B analyzes:                     │
│ - Understands math question              │
│ - Sees 'add' tool is available           │
│ - Decides to use it                      │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 4. Model Output                          │
│                                          │
│ <tool_call>                              │
│ {"name": "add",                          │
│  "arguments": {"a": 1, "b": 1}}          │
│ </tool_call>                             │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 5. ToolCallParser.parseToolCalls()       │
│                                          │
│ Regex: <tool_call>(.*?)</tool_call>      │
│ Extract JSON                             │
│ Create: ToolCall(name: "add",            │
│                  arguments: {a:1, b:1})  │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 6. ToolRegistry.executeToolCall()        │
│                                          │
│ registry.getTool("add")                  │
│ tool.execute({a: 1, b: 1})               │
│ Returns: 2                               │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 7. Format Result                         │
│                                          │
│ <tool_response>                          │
│ {"name": "add", "result": 2}             │
│ </tool_response>                         │
│                                          │
│ Please continue your response using      │
│ the tool results above.                  │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 8. Model Final Response                  │
│                                          │
│ "The answer is 2."                       │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ 9. User Sees                             │
│                                          │
│ [Tool: add({'a': 1, 'b': 1}) = 2]        │
│ The answer is 2.                         │
└──────────────────────────────────────────┘
```

## Multi-Turn Example: "(3 + 7) * 2"

```
Turn 1: User asks "(3 + 7) * 2"
  ↓
Turn 2: Model calls add(3, 7) → 10
  ↓
Turn 3: Model calls multiply(10, 2) → 20
  ↓
Turn 4: Model responds "The answer is 20"
```

## Component Interactions

```
┌─────────────────┐
│   UI Thread     │
│                 │
│  main.dart      │
│  • Shows chat   │
│  • Gets input   │
│  • Settings     │
└────────┬────────┘
         │ SendPort
         │
         ▼
┌─────────────────┐
│ Isolate Thread  │
│                 │
│ llama_isolate   │
│ llama_service   │
│ tool_calling    │
│                 │
│ • Runs model    │
│ • Parses tools  │
│ • Executes      │
└─────────────────┘
```

## Data Structures

```
┌─────────────────────────────────────────┐
│          ToolRegistry                   │
├─────────────────────────────────────────┤
│ Map<String, FunctionTool>               │
│                                         │
│ • register(tool)                        │
│ • getTool(name)                         │
│ • executeToolCall(call)                 │
└─────────────────────────────────────────┘
         │
         │ contains
         ▼
┌─────────────────────────────────────────┐
│          FunctionTool                   │
├─────────────────────────────────────────┤
│ String name                             │
│ String description                      │
│ List<FunctionParameter> parameters      │
│ Function execute                        │
│                                         │
│ • toJson() → JSON schema                │
│ • call(args) → dynamic result           │
└─────────────────────────────────────────┘
         │
         │ uses
         ▼
┌─────────────────────────────────────────┐
│      FunctionParameter                  │
├─────────────────────────────────────────┤
│ String name                             │
│ String type                             │
│ String description                      │
│ bool required                           │
└─────────────────────────────────────────┘
```

## Request Flow

```
User Input
    ↓
_formatPrompt() [adds tool definitions]
    ↓
Controller.runPromptStreaming()
    ↓
LlamaRequest(
    prompt,
    toolRegistry,
    useTools: true
)
    ↓
[Isolate Boundary]
    ↓
llamaIsolateEntry()
    ↓
if (useTools)
    → runPromptWithTools()
else
    → runPromptStreaming()
    ↓
Stream tokens back
    ↓
UI updates
```

## Error Handling

```
┌─────────────────────────────────────┐
│   Try to parse tool call            │
├─────────────────────────────────────┤
│   If parse fails:                   │
│   • Log error                       │
│   • Continue without tool           │
│   • Show original response          │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│   Try to execute tool               │
├─────────────────────────────────────┤
│   If execution fails:               │
│   • Catch exception                 │
│   • Return error as result          │
│   • Feed back to model              │
│   • Model can respond to error      │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│   Tool not found                    │
├─────────────────────────────────────┤
│   • Throw exception                 │
│   • Caught by executor              │
│   • Logged to console               │
└─────────────────────────────────────┘
```

## State Management

```
_ChatScreenState
    │
    ├─ _toolRegistry (ToolRegistry)
    │  └─ Initialized in initState()
    │
    ├─ _useToolCalling (bool)
    │  └─ Default: true
    │  └─ Toggle in settings
    │
    └─ When sending message:
       └─ if (_useToolCalling)
             Pass _toolRegistry
          else
             Pass null
```

## File Dependencies

```
main.dart
    ├─ import tool_calling.dart
    ├─ import built_in_tools.dart
    └─ import lcontroller.dart
           └─ import llama_request.dart
                  └─ import tool_calling.dart

llama_isolate.dart
    └─ import llama_service.dart
           └─ import tool_calling.dart

built_in_tools.dart
    └─ import tool_calling.dart
```

## Key Decision Points

```
1. Should we use tools?
   → Check _useToolCalling flag
   
2. Does output contain tool calls?
   → ToolCallParser.hasToolCalls()
   
3. Can we parse the tool call?
   → ToolCallParser.parseToolCalls()
   
4. Does the tool exist?
   → ToolRegistry.hasTool()
   
5. Can we execute it?
   → try { execute() } catch { error }
   
6. Should we continue?
   → Check iteration count < maxToolCalls
```
