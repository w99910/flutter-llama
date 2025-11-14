/// Quick integration guide: Add function calling to your existing chat app
///
/// This shows how to add automatic function calling to an existing chat
/// application with minimal code changes.

import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/internal/auto_function_executor.dart';
import 'package:flutter_application_1/internal/function_calling.dart';

/// BEFORE: Your existing chat code (without function calling)
class ChatWithoutFunctions {
  final LlamaService llamaService;

  ChatWithoutFunctions(this.llamaService);

  Future<String> sendMessage(String userInput) async {
    final prompt =
        '<|im_start|>user\n$userInput<|im_end|>\n<|im_start|>assistant\n';

    final buffer = StringBuffer();
    await llamaService.runPromptStreaming(
      prompt,
      (token) => buffer.write(token),
    );

    return buffer.toString();
  }
}

/// AFTER: Your chat with automatic function calling (3 line change!)
class ChatWithFunctions {
  final LlamaService llamaService;
  late final AutoFunctionExecutor executor; // ← Add this

  ChatWithFunctions(this.llamaService) {
    executor = AutoFunctionExecutor(llamaService); // ← Add this
  }

  Future<String> sendMessage(String userInput) async {
    final buffer = StringBuffer();

    // Replace runPromptStreaming with processUserInput
    await executor.processUserInput(
      // ← Change this line
      userInput,
      (token) => buffer.write(token),
    );

    return buffer.toString();
  }
}

/// That's it! Now your chat automatically:
/// - Detects when to call functions
/// - Executes them
/// - Returns the result
///
/// Example:
/// User: "What's 1+1?"
/// Model: "1 + 1 equals 2" (automatically called calculate function)

/// ═══════════════════════════════════════════════════════════════════════════
/// MORE EXAMPLES
/// ═══════════════════════════════════════════════════════════════════════════

/// Example 1: Add custom weather function
void exampleAddWeatherFunction() {
  final llamaService = LlamaService();
  llamaService.loadModel('/path/to/model.gguf');

  final executor = AutoFunctionExecutor(llamaService);

  // Add your custom function
  executor.registerFunction(
    LlamaFunction(
      name: 'get_weather',
      description: 'Get current weather for a city',
      parameters: {
        'type': 'object',
        'properties': {
          'city': {'type': 'string', 'description': 'City name'},
        },
        'required': ['city'],
      },
    ),
    (name, args) async {
      // Your weather API call here
      return {'temperature': 72, 'condition': 'Sunny', 'city': args['city']};
    },
  );

  // Now it works automatically!
  // User: "What's the weather in Paris?"
  // Model calls get_weather(city: "Paris")
  // Returns: "The weather in Paris is 72°F and sunny"
}

/// Example 2: Add database query function
void exampleAddDatabaseFunction() {
  final llamaService = LlamaService();
  llamaService.loadModel('/path/to/model.gguf');

  final executor = AutoFunctionExecutor(llamaService);

  executor.registerFunction(
    LlamaFunction(
      name: 'query_users',
      description: 'Search for users in the database',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'User name to search for'},
        },
        'required': ['name'],
      },
    ),
    (name, args) async {
      final searchName = args['name'] as String;
      // Your database query here
      // final results = await database.query(
      //   'SELECT * FROM users WHERE name LIKE ?',
      //   ['%$searchName%']
      // );
      return {
        'users': [
          {'id': 1, 'name': 'John Doe', 'email': 'john@example.com'},
          {'id': 2, 'name': 'Jane Doe', 'email': 'jane@example.com'},
        ],
        'query': searchName,
      };
    },
  );

  // User: "Find users named John"
  // Model automatically calls query_users(name: "John")
}

/// Example 3: Add file operations
void exampleAddFileOperations() {
  final llamaService = LlamaService();
  llamaService.loadModel('/path/to/model.gguf');

  final executor = AutoFunctionExecutor(llamaService);

  executor.registerFunction(
    LlamaFunction(
      name: 'read_file',
      description: 'Read contents of a file',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'File path to read'},
        },
        'required': ['path'],
      },
    ),
    (name, args) async {
      final path = args['path'] as String;

      // IMPORTANT: Validate paths for security!
      if (path.contains('..') || path.startsWith('/etc')) {
        throw Exception('Invalid path');
      }

      // Your file reading logic
      // final content = await File(path).readAsString();
      return {'content': 'File contents here...', 'size': 1234};
    },
  );
}

/// Example 4: Integration with Flutter StatefulWidget
///
/// ```dart
/// class ChatScreen extends StatefulWidget {
///   @override
///   State<ChatScreen> createState() => _ChatScreenState();
/// }
///
/// class _ChatScreenState extends State<ChatScreen> {
///   final LlamaService llamaService = LlamaService();
///   late AutoFunctionExecutor executor;
///   final List<String> messages = [];
///   bool isLoading = false;
///
///   @override
///   void initState() {
///     super.initState();
///     llamaService.loadModel('/path/to/model.gguf');
///     executor = AutoFunctionExecutor(llamaService);
///
///     // Add your custom functions
///     executor.registerFunction(yourFunction, yourHandler);
///   }
///
///   Future<void> sendMessage(String text) async {
///     setState(() {
///       messages.add('User: $text');
///       isLoading = true;
///     });
///
///     final response = StringBuffer();
///     await executor.processUserInput(
///       text,
///       (token) {
///         setState(() {
///           if (messages.last.startsWith('Assistant: ')) {
///             messages[messages.length - 1] = 'Assistant: ${response.toString()}$token';
///           } else {
///             messages.add('Assistant: $token');
///           }
///           response.write(token);
///         });
///       },
///     );
///
///     setState(() {
///       isLoading = false;
///     });
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: Column(
///         children: [
///           Expanded(
///             child: ListView.builder(
///               itemCount: messages.length,
///               itemBuilder: (context, index) {
///                 return ListTile(title: Text(messages[index]));
///               },
///             ),
///           ),
///           TextField(
///             onSubmitted: sendMessage,
///             decoration: InputDecoration(hintText: 'Type a message...'),
///           ),
///         ],
///       ),
///     );
///   }
///
///   @override
///   void dispose() {
///     llamaService.dispose();
///     super.dispose();
///   }
/// }
/// ```

/// Example 5: Add API calling functions
void exampleAddApiCalls() {
  final llamaService = LlamaService();
  llamaService.loadModel('/path/to/model.gguf');

  final executor = AutoFunctionExecutor(llamaService);

  // Add HTTP API function
  executor.registerFunction(
    LlamaFunction(
      name: 'fetch_url',
      description: 'Fetch data from a URL',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'URL to fetch'},
        },
        'required': ['url'],
      },
    ),
    (name, args) async {
      final url = args['url'] as String;

      // Validate URL for security
      final uri = Uri.parse(url);
      if (!uri.scheme.startsWith('http')) {
        throw Exception('Invalid URL scheme');
      }

      // Your HTTP call here
      // final response = await http.get(uri);
      return {'status': 200, 'body': 'Response data...'};
    },
  );

  // User: "Fetch data from https://api.example.com/data"
  // Model automatically calls fetch_url
}

/// ═══════════════════════════════════════════════════════════════════════════
/// TESTING YOUR FUNCTIONS
/// ═══════════════════════════════════════════════════════════════════════════

void testFunctionCalling() async {
  print("Testing automatic function calling...\n");

  final llamaService = LlamaService();
  llamaService.loadModel('/path/to/model.gguf');

  final executor = AutoFunctionExecutor(llamaService);

  // Test queries
  final testCases = [
    "What's 1+1?",
    "Calculate 25 * 48",
    "What time is it?",
    "Pick a random number between 1 and 10",
    "Calculate the square root of 144",
  ];

  for (final query in testCases) {
    print("═══════════════════════════════════════");
    print("User: $query");
    print("═══════════════════════════════════════");
    print("Assistant: ");

    await executor.processUserInput(
      query,
      (token) => print(token),
      verbose: true, // Shows function call details
    );

    print("\n");
  }

  llamaService.dispose();
}

/// ═══════════════════════════════════════════════════════════════════════════
/// TIPS & BEST PRACTICES
/// ═══════════════════════════════════════════════════════════════════════════

/// 1. Keep function descriptions clear and specific
/// Good: "Calculate mathematical expressions like 1+1, 5*3, sqrt(16)"
/// Bad: "Does math"

/// 2. Validate all inputs for security
/// - Check file paths don't escape allowed directories
/// - Validate URLs before fetching
/// - Sanitize database queries
/// - Limit number ranges

/// 3. Handle errors gracefully
/// Return error objects instead of throwing:
/// ```dart
/// return {
///   'success': false,
///   'error': 'Invalid input',
///   'details': 'Path contains invalid characters'
/// };
/// ```

/// 4. Use appropriate temperature
/// - 0.3 for reliable function calling
/// - 0.7 for balanced
/// - Avoid > 0.8 (may break JSON format)

/// 5. Limit function call depth
/// ```dart
/// await executor.processUserInput(
///   input,
///   onToken,
///   maxFunctionCalls: 3, // Prevent infinite loops
/// );
/// ```

/// 6. Test with and without grammar
/// ```dart
/// // With grammar (recommended)
/// await llamaService.runPromptWithFunctions(
///   prompt, functions, onToken,
///   useGrammar: true,  // Ensures valid JSON
/// );
/// 
/// // Without grammar (for native function calling models)
/// await llamaService.runPromptWithFunctions(
///   prompt, functions, onToken,
///   useGrammar: false,
/// );
/// ```

/// 7. Monitor performance
/// - Function definitions add tokens to context
/// - More functions = slower inference
/// - Only register functions relevant to the task

/// 8. Use conversation history for context
/// ```dart
/// final history = <Map<String, String>>[];
/// 
/// await executor.processUserInput(
///   "Calculate 5 * 5",
///   onToken,
///   conversationHistory: history,
/// );
/// 
/// await executor.processUserInput(
///   "Multiply that by 2",  // Model remembers previous result
///   onToken,
///   conversationHistory: history,
/// );
/// ```
