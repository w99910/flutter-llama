import 'dart:convert';

/// Represents a function parameter
class FunctionParameter {
  final String name;
  final String type;
  final String description;
  final bool required;

  FunctionParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = true,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'description': description,
      };
}

/// Represents a callable tool/function
class FunctionTool {
  final String name;
  final String description;
  final List<FunctionParameter> parameters;
  final Function(Map<String, dynamic>) execute;

  FunctionTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  /// Convert to JSON schema format for Qwen3
  Map<String, dynamic> toJson() {
    final properties = <String, dynamic>{};
    final required = <String>[];

    for (final param in parameters) {
      properties[param.name] = param.toJson();
      if (param.required) {
        required.add(param.name);
      }
    }

    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': required,
        },
      },
    };
  }

  /// Execute the tool with provided arguments
  dynamic call(Map<String, dynamic> arguments) {
    return execute(arguments);
  }
}

/// Represents a tool call parsed from model output
class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  ToolCall({required this.name, required this.arguments});

  @override
  String toString() => 'ToolCall(name: $name, arguments: $arguments)';
}

/// Registry for managing available tools
class ToolRegistry {
  final Map<String, FunctionTool> _tools = {};

  /// Register a new tool
  void register(FunctionTool tool) {
    _tools[tool.name] = tool;
  }

  /// Get a tool by name
  FunctionTool? getTool(String name) {
    return _tools[name];
  }

  /// Get all tools as JSON array for prompt
  List<Map<String, dynamic>> toJsonList() {
    return _tools.values.map((tool) => tool.toJson()).toList();
  }

  /// Check if a tool exists
  bool hasTool(String name) {
    return _tools.containsKey(name);
  }

  /// Execute a tool call
  dynamic executeToolCall(ToolCall call) {
    final tool = _tools[call.name];
    if (tool == null) {
      throw Exception('Tool not found: ${call.name}');
    }
    return tool.call(call.arguments);
  }
}

/// Utility class for parsing tool calls from Qwen3 output
class ToolCallParser {
  /// Parse tool calls from model output
  /// Qwen3 format: <tool_call>{"name": "function_name", "arguments": {...}}</tool_call>
  static List<ToolCall> parseToolCalls(String text) {
    final toolCalls = <ToolCall>[];
    final regex = RegExp(
      r'<tool_call>\s*({.*?})\s*</tool_call>',
      dotAll: true,
    );

    final matches = regex.allMatches(text);
    for (final match in matches) {
      try {
        final jsonStr = match.group(1);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final name = json['name'] as String;
          final arguments = json['arguments'] as Map<String, dynamic>;
          toolCalls.add(ToolCall(name: name, arguments: arguments));
        }
      } catch (e) {
        print('Failed to parse tool call: $e');
      }
    }

    return toolCalls;
  }

  /// Check if text contains tool calls
  static bool hasToolCalls(String text) {
    return text.contains('<tool_call>');
  }

  /// Extract text before tool calls
  static String extractTextBeforeToolCalls(String text) {
    final idx = text.indexOf('<tool_call>');
    if (idx == -1) return text;
    return text.substring(0, idx).trim();
  }

  /// Remove tool call tags from text
  static String removeToolCallTags(String text) {
    return text.replaceAll(RegExp(r'<tool_call>.*?</tool_call>', dotAll: true), '').trim();
  }
}

/// Format tools for Qwen3 system prompt
String formatToolsForPrompt(ToolRegistry registry) {
  final tools = registry.toJsonList();
  if (tools.isEmpty) return '';

  final toolsJson = jsonEncode(tools);
  return '''
You have access to the following tools:

$toolsJson

IMPORTANT: Only use these tools when the user's question specifically requires them. 
- Use tools ONLY for calculations or tasks that match their exact purpose
- For general knowledge questions (like "what is bitcoin"), answer directly without using any tools
- For greetings, conversations, or explanations, respond normally without tools

When you need to use a tool, respond with:
<tool_call>
{"name": "tool_name", "arguments": {"param1": "value1", "param2": "value2"}}
</tool_call>

After receiving the tool result, continue your response naturally.''';
}

/// Create a tool result message for Qwen3
String formatToolResult(String toolName, dynamic result) {
  return '''<tool_response>
{"name": "$toolName", "result": ${jsonEncode(result)}}
</tool_response>''';
}
