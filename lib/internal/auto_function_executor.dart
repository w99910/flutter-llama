import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/internal/function_calling.dart';

/// Callback type for function execution
typedef FunctionExecutor =
    Future<dynamic> Function(
      String functionName,
      Map<String, dynamic> arguments,
    );

/// Automatic function calling system that handles the entire loop:
/// 1. User asks a question
/// 2. Model decides if it needs to call a function
/// 3. Function is called automatically
/// 4. Result is fed back to model
/// 5. Model generates final response
class AutoFunctionExecutor {
  final LlamaService llamaService;
  final Map<String, FunctionExecutor> _functionHandlers = {};
  final List<LlamaFunction> _availableFunctions = [];

  AutoFunctionExecutor(this.llamaService) {
    _registerBuiltInFunctions();
  }

  /// Register a custom function handler
  void registerFunction(LlamaFunction function, FunctionExecutor handler) {
    _availableFunctions.add(function);
    _functionHandlers[function.name] = handler;
  }

  /// Register built-in functions (calculator, time, etc.)
  void _registerBuiltInFunctions() {
    // Calculator function
    registerFunction(
      LlamaFunction(
        name: 'calculate',
        description:
            'Perform mathematical calculations. Supports basic operations (+, -, *, /), powers (^), square root (sqrt), and parentheses.',
        parameters: {
          'type': 'object',
          'properties': {
            'expression': {
              'type': 'string',
              'description':
                  'The mathematical expression to evaluate, e.g., "1+1", "25*48+120", "sqrt(144)"',
            },
          },
          'required': ['expression'],
        },
      ),
      _handleCalculate,
    );

    // Current time function
    registerFunction(
      LlamaFunction(
        name: 'get_current_time',
        description: 'Get the current date and time',
        parameters: {
          'type': 'object',
          'properties': {
            'timezone': {
              'type': 'string',
              'description': 'Optional timezone (defaults to local)',
            },
          },
        },
      ),
      _handleGetTime,
    );

    // Random number generator
    registerFunction(
      LlamaFunction(
        name: 'generate_random_number',
        description: 'Generate a random number within a range',
        parameters: {
          'type': 'object',
          'properties': {
            'min': {
              'type': 'number',
              'description': 'Minimum value (inclusive)',
            },
            'max': {
              'type': 'number',
              'description': 'Maximum value (inclusive)',
            },
          },
          'required': ['min', 'max'],
        },
      ),
      _handleRandomNumber,
    );
  }

  /// Main method: Process user input with automatic function calling
  /// Returns the final response after potentially calling functions
  Future<String> processUserInput(
    String userInput,
    void Function(String token) onToken, {
    List<Map<String, String>>? conversationHistory,
    int maxFunctionCalls = 5, // Prevent infinite loops
    bool verbose = true,
  }) async {
    if (verbose) {
      print("\n═══════════════════════════════════════");
      print("🤖 Processing: $userInput");
      print("═══════════════════════════════════════\n");
    }

    // Build conversation history
    final history = conversationHistory ?? [];
    history.add({'role': 'user', 'content': userInput});

    int callCount = 0;
    bool shouldContinue = true;

    while (shouldContinue && callCount < maxFunctionCalls) {
      // Generate prompt with tools
      final prompt = _buildPromptWithTools(history);

      if (verbose && callCount > 0) {
        print("\n🔄 Function call round ${callCount + 1}...\n");
      }

      // Try to get function call from model
      String modelOutput = "";
      final result = await llamaService.runPromptWithFunctions(
        prompt,
        _availableFunctions,
        (token) {
          modelOutput += token;
          if (callCount == 0 || !_isValidFunctionCallJSON(modelOutput)) {
            // Only stream to user on first call or if it's not a function call
            onToken(token);
          }
        },
        useGrammar: false, // Disabled: Small models can crash with grammar constraints
        temperature: 0.3, // Lower temperature for reliable function calling
        maxTokens: 512,
      );

      if (verbose) {
        print("\n\n📥 Model output: $result\n");
      }

      // Clean the output - remove reasoning tags and extra text
      final cleanedResult = _cleanModelOutput(result.trim());

      if (verbose && cleanedResult != result.trim()) {
        print("🧹 Cleaned output: $cleanedResult\n");
      }

      // Check if model wants to call a function
      final functionCalls = FunctionCallingHelper.parseFunctionCalls(
        cleanedResult,
      );

      if (functionCalls != null && functionCalls.isNotEmpty) {
        // Model wants to call function(s)
        callCount++;

        if (verbose) {
          print("🔧 Detected ${functionCalls.length} function call(s)\n");
        }

        // Execute all function calls
        for (final call in functionCalls) {
          if (verbose) {
            print("  📞 Calling: ${call.name}");
            print("  📋 Arguments: ${jsonEncode(call.arguments)}");
          }

          // Execute the function
          final functionResult = await _executeFunction(call);

          if (verbose) {
            print("  ✅ Result: ${jsonEncode(functionResult)}\n");
          }

          // Add function call and result to history
          history.add({
            'role': 'assistant',
            'content': jsonEncode(call.toJson()),
          });
          history.add({
            'role': 'function',
            'name': call.name,
            'content': jsonEncode(functionResult),
          });
        }

        // Continue loop to get final response
        shouldContinue = true;
      } else {
        // Model responded directly, no function call needed
        if (verbose && callCount > 0) {
          print("✅ Final response generated\n");
        }

        // Add assistant's final response to history
        history.add({'role': 'assistant', 'content': result.trim()});

        shouldContinue = false;
        return result.trim();
      }
    }

    if (callCount >= maxFunctionCalls) {
      final errorMsg = "⚠️  Max function calls ($maxFunctionCalls) reached";
      print(errorMsg);
      return errorMsg;
    }

    return "";
  }

  /// Build a prompt with conversation history and tool definitions
  String _buildPromptWithTools(List<Map<String, String>> history) {
    final systemPrompt = FunctionCallingHelper.formatToolsSystemPrompt(
      _availableFunctions,
    );

    // Build the prompt in ChatML format
    final buffer = StringBuffer();
    buffer.write('<|im_start|>system\n');
    buffer.write(systemPrompt);
    buffer.write('<|im_end|>\n');

    for (final message in history) {
      final role = message['role']!;
      final content = message['content']!;

      if (role == 'function') {
        // Special handling for function results
        buffer.write('<|im_start|>function\n');
        buffer.write('name=${message['name']}\n');
        buffer.write(content);
        buffer.write('<|im_end|>\n');
      } else {
        buffer.write('<|im_start|>$role\n');
        buffer.write(content);
        buffer.write('<|im_end|>\n');
      }
    }

    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  /// Execute a function call
  Future<dynamic> _executeFunction(FunctionCall call) async {
    final handler = _functionHandlers[call.name];

    if (handler == null) {
      return {
        'error': 'Function ${call.name} not found',
        'available_functions': _functionHandlers.keys.toList(),
      };
    }

    try {
      return await handler(call.name, call.arguments);
    } catch (e) {
      return {'error': 'Function execution failed: $e'};
    }
  }

  /// Check if string looks like valid function call JSON (heuristic)
  bool _isValidFunctionCallJSON(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('{') &&
        (trimmed.contains('"name"') || trimmed.contains('"tool_calls"'));
  }

  /// Clean model output - remove reasoning tags and extract JSON
  String _cleanModelOutput(String output) {
    String cleaned = output;

    // Remove <think> and </think> tags and their content (for reasoning models)
    cleaned = cleaned.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true),
      '',
    );

    // Remove markdown code blocks
    cleaned = cleaned.replaceAll(RegExp(r'```json\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'```\s*'), '');

    // Try to extract JSON object if surrounded by text
    final jsonMatch = RegExp(r'\{[^{}]*"name"[^{}]*\}').firstMatch(cleaned);
    if (jsonMatch != null) {
      cleaned = jsonMatch.group(0)!;
    }

    // Remove any leading/trailing whitespace and newlines
    cleaned = cleaned.trim();

    return cleaned;
  }

  // Built-in function handlers

  /// Calculate mathematical expressions
  Future<dynamic> _handleCalculate(
    String functionName,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final expression = arguments['expression'] as String;

      // Simple math parser - replace with a proper math library for production
      final result = _evaluateExpression(expression);

      return {'expression': expression, 'result': result, 'success': true};
    } catch (e) {
      return {'error': 'Failed to calculate: $e', 'success': false};
    }
  }

  /// Simple expression evaluator (supports +, -, *, /, ^, sqrt, parentheses)
  /// For production, use a library like math_expressions
  double _evaluateExpression(String expr) {
    // Remove whitespace
    expr = expr.replaceAll(' ', '');

    // Handle sqrt
    while (expr.contains('sqrt(')) {
      final start = expr.indexOf('sqrt(');
      int depth = 0;
      int end = start + 5;
      for (; end < expr.length; end++) {
        if (expr[end] == '(') depth++;
        if (expr[end] == ')') {
          if (depth == 0) break;
          depth--;
        }
      }
      final inner = expr.substring(start + 5, end);
      final value = math.sqrt(_evaluateExpression(inner));
      expr =
          expr.substring(0, start) + value.toString() + expr.substring(end + 1);
    }

    // Handle parentheses
    while (expr.contains('(')) {
      final start = expr.lastIndexOf('(');
      final end = expr.indexOf(')', start);
      final inner = expr.substring(start + 1, end);
      final value = _evaluateExpression(inner);
      expr =
          expr.substring(0, start) + value.toString() + expr.substring(end + 1);
    }

    // Handle power (^)
    if (expr.contains('^')) {
      final parts = expr.split('^');
      var result = _evaluateExpression(parts[0]);
      for (int i = 1; i < parts.length; i++) {
        result = math.pow(result, _evaluateExpression(parts[i])).toDouble();
      }
      return result;
    }

    // Handle multiplication and division (left to right)
    final mulDivRegex = RegExp(r'(-?\d+\.?\d*)([*/])(-?\d+\.?\d*)');
    while (mulDivRegex.hasMatch(expr)) {
      final match = mulDivRegex.firstMatch(expr)!;
      final left = double.parse(match.group(1)!);
      final op = match.group(2)!;
      final right = double.parse(match.group(3)!);
      final result = op == '*' ? left * right : left / right;
      expr = expr.replaceFirst(match.group(0)!, result.toString());
    }

    // Handle addition and subtraction (left to right)
    final addSubRegex = RegExp(r'(-?\d+\.?\d*)([+\-])(-?\d+\.?\d*)');
    while (addSubRegex.hasMatch(expr)) {
      final match = addSubRegex.firstMatch(expr)!;
      final left = double.parse(match.group(1)!);
      final op = match.group(2)!;
      final right = double.parse(match.group(3)!);
      final result = op == '+' ? left + right : left - right;
      expr = expr.replaceFirst(match.group(0)!, result.toString());
    }

    return double.parse(expr);
  }

  /// Get current time
  Future<dynamic> _handleGetTime(
    String functionName,
    Map<String, dynamic> arguments,
  ) async {
    final now = DateTime.now();
    return {
      'datetime': now.toIso8601String(),
      'date':
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      'timezone': now.timeZoneName,
      'timestamp': now.millisecondsSinceEpoch,
    };
  }

  /// Generate random number
  Future<dynamic> _handleRandomNumber(
    String functionName,
    Map<String, dynamic> arguments,
  ) async {
    final min = (arguments['min'] as num).toInt();
    final max = (arguments['max'] as num).toInt();
    final random = math.Random();
    final result = min + random.nextInt(max - min + 1);

    return {'number': result, 'min': min, 'max': max};
  }

  /// Get list of available functions
  List<String> getAvailableFunctions() {
    return _availableFunctions.map((f) => f.name).toList();
  }

  /// Get function details
  LlamaFunction? getFunction(String name) {
    try {
      return _availableFunctions.firstWhere((f) => f.name == name);
    } catch (e) {
      return null;
    }
  }
}
