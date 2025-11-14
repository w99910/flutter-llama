import 'dart:convert';

/// Represents a function/tool that can be called by the LLM
class LlamaFunction {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  LlamaFunction({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Convert to OpenAI-compatible tool format
  Map<String, dynamic> toToolFormat() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }

  /// Generate GBNF grammar for this function's parameters
  /// This constrains the model to output valid JSON matching the schema
  String toGBNFGrammar() {
    // For now, generate a simple JSON grammar
    // In production, you'd want to generate schema-specific grammar
    return _generateJSONGrammar();
  }

  /// Generate a basic JSON grammar (GBNF format)
  /// For production, use json-schema-to-grammar converter
  String _generateJSONGrammar() {
    return '''
root ::= object
value ::= object | array | string | number | boolean | null
object ::= "{" ws ( member ( "," ws member )* )? "}" ws
member ::= string ":" ws value
array ::= "[" ws ( value ( "," ws value )* )? "]" ws
string ::= "\\"" ( [^"\\\\] | "\\\\" ["\\\\/bfnrt] | "\\\\u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] )* "\\""
number ::= ( "-"? ( "0" | [1-9] [0-9]* ) ) ( "." [0-9]+ )? ( [eE] [-+]? [0-9]+ )?
boolean ::= "true" | "false"
null ::= "null"
ws ::= [ \\t\\n]*
''';
  }
}

/// Represents a function call extracted from model output
class FunctionCall {
  final String name;
  final Map<String, dynamic> arguments;

  FunctionCall({required this.name, required this.arguments});

  factory FunctionCall.fromJson(Map<String, dynamic> json) {
    return FunctionCall(
      name: json['name'] as String,
      arguments: json['arguments'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'arguments': arguments};
  }
}

/// Utility class for function calling support
class FunctionCallingHelper {
  /// Format a system prompt with available tools (for models without native support)
  /// This is used for "generic" function calling mode
  static String formatToolsSystemPrompt(List<LlamaFunction> tools) {
    final toolsJson = tools.map((t) => t.toToolFormat()).toList();
    return '''You are a helpful assistant with access to the following tools:

${jsonEncode(toolsJson)}

CRITICAL INSTRUCTIONS:
1. When you need to use a tool, you MUST respond with ONLY a JSON object in this exact format:
   {"name": "function_name", "arguments": {"param1": "value1"}}

2. DO NOT include any other text, explanations, or thoughts.
3. DO NOT use <think> tags or reasoning steps.
4. DO NOT explain your reasoning.
5. Just output the JSON object directly.

Example:
User: "What's 1+1?"
Assistant: {"name": "calculate", "arguments": {"expression": "1+1"}}

If you don't need to call a tool, respond normally with a helpful answer.''';
  }

  /// Format tools for native function calling models (Llama 3.1+, etc.)
  /// These models expect tools in their chat template
  static String formatToolsForNative(List<LlamaFunction> tools) {
    // For native models, the chat template handles tool formatting
    // Just return the tools in OpenAI format
    return jsonEncode(tools.map((t) => t.toToolFormat()).toList());
  }

  /// Parse function call from model output
  /// Supports both native format and generic JSON format
  static List<FunctionCall>? parseFunctionCalls(String output) {
    try {
      // Try to parse as JSON
      final decoded = jsonDecode(output);

      if (decoded is Map<String, dynamic>) {
        // Check for tool_calls array (native format)
        if (decoded.containsKey('tool_calls')) {
          final toolCalls = decoded['tool_calls'] as List;
          return toolCalls
              .map(
                (call) => FunctionCall(
                  name: call['function']['name'] as String,
                  arguments:
                      call['function']['arguments'] as Map<String, dynamic>,
                ),
              )
              .toList();
        }

        // Check for direct function call format
        if (decoded.containsKey('name') && decoded.containsKey('arguments')) {
          return [
            FunctionCall(
              name: decoded['name'] as String,
              arguments: decoded['arguments'] as Map<String, dynamic>,
            ),
          ];
        }
      }

      return null;
    } catch (e) {
      // Not a function call, return null
      return null;
    }
  }

  /// Format function result for feeding back to the model
  static String formatFunctionResult(String functionName, dynamic result) {
    return jsonEncode({
      'tool_call_id': functionName,
      'role': 'tool',
      'name': functionName,
      'content': result.toString(),
    });
  }

  /// Create a grammar string for function calling
  /// This constrains the model to output valid function call JSON
  static String createFunctionCallGrammar(List<LlamaFunction> functions) {
    // Build a GBNF grammar that matches the function call format
    final functionNames = functions.map((f) => '"${f.name}"').join(' | ');

    return '''
root ::= function-call
function-call ::= "{" ws "\\"name\\"" ws ":" ws function-name ws "," ws "\\"arguments\\"" ws ":" ws arguments ws "}"
function-name ::= $functionNames
arguments ::= object
object ::= "{" ws ( member ( "," ws member )* )? "}" ws
member ::= string ":" ws value
value ::= object | array | string | number | boolean | null
array ::= "[" ws ( value ( "," ws value )* )? "]" ws
string ::= "\\"" ( [^"\\\\] | "\\\\" ["\\\\/bfnrt] | "\\\\u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] )* "\\""
number ::= ( "-"? ( "0" | [1-9] [0-9]* ) ) ( "." [0-9]+ )? ( [eE] [-+]? [0-9]+ )?
boolean ::= "true" | "false"
null ::= "null"
ws ::= [ \\t\\n]*
''';
  }
}

/// Example tool definitions
class ExampleTools {
  static LlamaFunction get weatherTool => LlamaFunction(
    name: 'get_current_weather',
    description: 'Get the current weather in a given location',
    parameters: {
      'type': 'object',
      'properties': {
        'location': {
          'type': 'string',
          'description': 'The city and state, e.g. San Francisco, CA',
        },
        'unit': {
          'type': 'string',
          'enum': ['celsius', 'fahrenheit'],
          'description': 'The temperature unit',
        },
      },
      'required': ['location'],
    },
  );

  static LlamaFunction get pythonTool => LlamaFunction(
    name: 'python',
    description: 'Runs code in a Python interpreter and returns the result',
    parameters: {
      'type': 'object',
      'properties': {
        'code': {'type': 'string', 'description': 'The Python code to execute'},
      },
      'required': ['code'],
    },
  );

  static LlamaFunction get searchTool => LlamaFunction(
    name: 'web_search',
    description: 'Search the web for information',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'The search query'},
      },
      'required': ['query'],
    },
  );

  static LlamaFunction get calculatorTool => LlamaFunction(
    name: 'calculate',
    description: 'Perform mathematical calculations',
    parameters: {
      'type': 'object',
      'properties': {
        'expression': {
          'type': 'string',
          'description': 'The mathematical expression to evaluate',
        },
      },
      'required': ['expression'],
    },
  );
}
