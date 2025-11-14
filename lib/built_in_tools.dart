import 'tool_calling.dart';

/// Create and return a registry with built-in tools
ToolRegistry createBuiltInTools() {
  final registry = ToolRegistry();

  // Add function: adds two numbers
  registry.register(
    FunctionTool(
      name: 'add',
      description: 'Add two numbers together and return the result',
      parameters: [
        FunctionParameter(
          name: 'a',
          type: 'number',
          description: 'The first number to add',
          required: true,
        ),
        FunctionParameter(
          name: 'b',
          type: 'number',
          description: 'The second number to add',
          required: true,
        ),
      ],
      execute: (arguments) {
        final a = arguments['a'];
        final b = arguments['b'];
        
        // Handle both int and double
        double numA = (a is int) ? a.toDouble() : (a as num).toDouble();
        double numB = (b is int) ? b.toDouble() : (b as num).toDouble();
        
        final result = numA + numB;
        
        // Return as int if the result is a whole number
        if (result == result.toInt()) {
          return result.toInt();
        }
        return result;
      },
    ),
  );

  // Subtract function: subtracts two numbers
  registry.register(
    FunctionTool(
      name: 'subtract',
      description: 'Subtract second number from the first number',
      parameters: [
        FunctionParameter(
          name: 'a',
          type: 'number',
          description: 'The number to subtract from',
          required: true,
        ),
        FunctionParameter(
          name: 'b',
          type: 'number',
          description: 'The number to subtract',
          required: true,
        ),
      ],
      execute: (arguments) {
        final a = arguments['a'];
        final b = arguments['b'];
        
        double numA = (a is int) ? a.toDouble() : (a as num).toDouble();
        double numB = (b is int) ? b.toDouble() : (b as num).toDouble();
        
        final result = numA - numB;
        
        if (result == result.toInt()) {
          return result.toInt();
        }
        return result;
      },
    ),
  );

  // Multiply function: multiplies two numbers
  registry.register(
    FunctionTool(
      name: 'multiply',
      description: 'Multiply two numbers together',
      parameters: [
        FunctionParameter(
          name: 'a',
          type: 'number',
          description: 'The first number to multiply',
          required: true,
        ),
        FunctionParameter(
          name: 'b',
          type: 'number',
          description: 'The second number to multiply',
          required: true,
        ),
      ],
      execute: (arguments) {
        final a = arguments['a'];
        final b = arguments['b'];
        
        double numA = (a is int) ? a.toDouble() : (a as num).toDouble();
        double numB = (b is int) ? b.toDouble() : (b as num).toDouble();
        
        final result = numA * numB;
        
        if (result == result.toInt()) {
          return result.toInt();
        }
        return result;
      },
    ),
  );

  // Divide function: divides two numbers
  registry.register(
    FunctionTool(
      name: 'divide',
      description: 'Divide the first number by the second number',
      parameters: [
        FunctionParameter(
          name: 'a',
          type: 'number',
          description: 'The dividend (number to be divided)',
          required: true,
        ),
        FunctionParameter(
          name: 'b',
          type: 'number',
          description: 'The divisor (number to divide by)',
          required: true,
        ),
      ],
      execute: (arguments) {
        final a = arguments['a'];
        final b = arguments['b'];
        
        double numA = (a is int) ? a.toDouble() : (a as num).toDouble();
        double numB = (b is int) ? b.toDouble() : (b as num).toDouble();
        
        if (numB == 0) {
          throw Exception('Cannot divide by zero');
        }
        
        final result = numA / numB;
        
        if (result == result.toInt()) {
          return result.toInt();
        }
        return result;
      },
    ),
  );

  return registry;
}
