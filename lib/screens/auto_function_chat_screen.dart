import 'package:flutter/material.dart';
import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/internal/auto_function_executor.dart';

/// Flutter chat interface with automatic function calling
///
/// Usage:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (context) => AutoFunctionChatScreen(
///       llamaService: yourLlamaService,
///     ),
///   ),
/// );
/// ```
class AutoFunctionChatScreen extends StatefulWidget {
  final LlamaService llamaService;
  final String title;

  const AutoFunctionChatScreen({
    super.key,
    required this.llamaService,
    this.title = 'AI Assistant with Tools',
  });

  @override
  State<AutoFunctionChatScreen> createState() => _AutoFunctionChatScreenState();
}

class _AutoFunctionChatScreenState extends State<AutoFunctionChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  late AutoFunctionExecutor _executor;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _executor = AutoFunctionExecutor(widget.llamaService);

    // Add welcome message
    _messages.add(
      ChatMessage(
        text:
            'Hello! I can help you with calculations, time, and random numbers. Try asking me to:\n'
            '• Calculate math expressions (e.g., "What\'s 1+1?")\n'
            '• Get the current time\n'
            '• Generate random numbers\n\n'
            'I\'ll automatically call the appropriate functions when needed!',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(String text) async {
    if (text.trim().isEmpty || _isProcessing) return;

    final userMessage = text.trim();
    _textController.clear();

    setState(() {
      _messages.add(
        ChatMessage(text: userMessage, isUser: true, timestamp: DateTime.now()),
      );
      _isProcessing = true;
    });

    _scrollToBottom();

    // Add placeholder for assistant's response
    final assistantMessageIndex = _messages.length;
    setState(() {
      _messages.add(
        ChatMessage(
          text: '',
          isUser: false,
          timestamp: DateTime.now(),
          isStreaming: true,
        ),
      );
    });

    try {
      // Process with automatic function calling
      final buffer = StringBuffer();

      await _executor.processUserInput(
        userMessage,
        (token) {
          // Update the message as tokens stream in
          buffer.write(token);
          setState(() {
            _messages[assistantMessageIndex] = ChatMessage(
              text: buffer.toString(),
              isUser: false,
              timestamp: _messages[assistantMessageIndex].timestamp,
              isStreaming: true,
            );
          });
          _scrollToBottom();
        },
        verbose: false, // Don't show debug logs in UI
      );

      // Mark streaming as complete
      setState(() {
        _messages[assistantMessageIndex] = ChatMessage(
          text: buffer.toString(),
          isUser: false,
          timestamp: _messages[assistantMessageIndex].timestamp,
          isStreaming: false,
        );
      });
    } catch (e) {
      setState(() {
        _messages[assistantMessageIndex] = ChatMessage(
          text: '❌ Error: $e',
          isUser: false,
          timestamp: _messages[assistantMessageIndex].timestamp,
          isStreaming: false,
          isError: true,
        );
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showAvailableFunctions() {
    final functions = _executor.getAvailableFunctions();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Available Functions'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: functions.map((name) {
              final func = _executor.getFunction(name);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      func?.description ?? '',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.functions),
            tooltip: 'View available functions',
            onPressed: _showAvailableFunctions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Available functions banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Functions available: ${_executor.getAvailableFunctions().join(", ")}',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ChatMessageWidget(message: _messages[index]);
              },
            ),
          ),

          // Input area
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Ask me anything...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _handleSubmit,
                    enabled: !_isProcessing,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _isProcessing
                      ? null
                      : () => _handleSubmit(_textController.text),
                  tooltip: 'Send',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual chat message model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isStreaming;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
    this.isError = false,
  });
}

/// Widget to display a single chat message
class ChatMessageWidget extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: message.isError ? Colors.red : Colors.blue,
              child: Icon(
                message.isError ? Icons.error : Icons.smart_toy,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? Colors.blue
                        : (message.isError ? Colors.red[50] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.text.isEmpty && message.isStreaming
                            ? '...'
                            : message.text,
                        style: TextStyle(
                          color: message.isUser
                              ? Colors.white
                              : (message.isError
                                    ? Colors.red[900]
                                    : Colors.black87),
                        ),
                      ),
                      if (message.isStreaming && message.text.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 12),
            const CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.person, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Example usage in your app:
/// 
/// ```dart
/// // In your main.dart or wherever you initialize LlamaService
/// class MyApp extends StatefulWidget {
///   @override
///   State<MyApp> createState() => _MyAppState();
/// }
/// 
/// class _MyAppState extends State<MyApp> {
///   late LlamaService llamaService;
///   bool isModelLoaded = false;
/// 
///   @override
///   void initState() {
///     super.initState();
///     _initModel();
///   }
/// 
///   Future<void> _initModel() async {
///     llamaService = LlamaService();
///     final success = llamaService.loadModel('/path/to/model.gguf');
///     setState(() {
///       isModelLoaded = success;
///     });
///   }
/// 
///   @override
///   Widget build(BuildContext context) {
///     return MaterialApp(
///       home: isModelLoaded
///           ? AutoFunctionChatScreen(llamaService: llamaService)
///           : Scaffold(
///               body: Center(child: CircularProgressIndicator()),
///             ),
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
