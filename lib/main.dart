import 'package:flutter/material.dart';

// Correct imports for FFI and Platform detection
import 'dart:io';

import 'package:flutter_application_1/internal/huggingface.dart';
import 'package:flutter_application_1/internal/llama_request.dart';
import 'package:flutter_application_1/lcontroller.dart';

import 'package:path_provider/path_provider.dart';

// STEP 1: DEFINE A DATA CLASS TO PASS ARGUMENTS (BEST PRACTICE)

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Llama Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 55, 132, 231),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

// A simple data class for a chat message.
class ChatMessage {
  final String text;
  final bool isUser;
  final String? thinking; // Optional thinking process for Qwen models

  ChatMessage({required this.text, required this.isUser, this.thinking});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // The controller that manages the background isolate and Llama service.
  LlamaController _controller = LlamaController();

  // UI state variables
  bool _isModelReady = false;
  bool _isAssistantTyping = false;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  // Generation parameters - can be adjusted by the user
  double _temperature = 0.8;
  int _topK = 40;
  double _topP = 0.95;
  double _minP = 0.05;

  // Current model configuration
  // String _currentRepoId = "unsloth/gemma-3-270m-it-GGUF";
  // String _currentFileName = "gemma-3-270m-it-Q8_0.gguf";

  String _currentRepoId = "unsloth/Qwen3-0.6B-GGUF";
  String _currentFileName = "Qwen3-0.6B-Q4_K_M.gguf";

  // Detect model type from filename
  String get _modelType {
    final lowerName = _currentFileName.toLowerCase();
    if (lowerName.contains('qwen')) {
      return 'qwen';
    } else if (lowerName.contains('gemma')) {
      return 'gemma';
    }
    // Default to gemma if unknown
    return 'gemma';
  }

  @override
  void initState() {
    super.initState();
    _initializeLlama();
  }

  @override
  void dispose() {
    // IMPORTANT: Clean up the controller and isolate when the widget is disposed.
    _controller.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Initializes the Llama controller and updates the UI state.
  void _initializeLlama() async {
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/$_currentFileName';
    final file = File(savePath);
    if (!file.existsSync()) {
      print("Downloading..");
      await downloadGGUF(
        repoId: _currentRepoId,
        filename: _currentFileName,
        path: savePath,
      );
      print("Downloaded at $savePath");
    } else {
      print("Model file exists at path: $savePath");
      print("Model file size: ${await file.length()} bytes");
    }
    // Show an initial message to the user.
    setState(() {
      _messages.add(
        ChatMessage(
          text:
              "Initializing model... Please wait.\nThis can take a minute depending on the model size.",
          isUser: false,
        ),
      );
    });

    await _controller.initialize(modelPath: savePath);

    // Update the UI once the model is loaded and ready.
    setState(() {
      _messages.removeLast(); // Remove the "Initializing" message
      _messages.add(
        ChatMessage(
          text: "Model ready! How can I help you today?",
          isUser: false,
        ),
      );
      _isModelReady = true;
    });
  }

  /// Formats the prompt using Gemma chat template
  String _formatPromptForGemma(String userMessage) {
    // Gemma chat template format
    return "<start_of_turn>user\n$userMessage<end_of_turn>\n<start_of_turn>model\n";
  }

  /// Formats the prompt using Qwen chat template
  String _formatPromptForQwen(String userMessage) {
    // Qwen official chat template format (standard version without thinking)
    // Based on: https://github.com/QwenLM/Qwen/blob/main/docs/chat_template.md
    return "<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n";
  }

  /// Formats the prompt based on the detected model type
  String _formatPrompt(String userMessage) {
    switch (_modelType) {
      case 'qwen':
        return _formatPromptForQwen(userMessage);
      case 'gemma':
      default:
        return _formatPromptForGemma(userMessage);
    }
  }

  /// Handles sending the prompt to the Llama model.
  void _handleSendPrompt() async {
    final prompt = _textController.text.trim();
    if (prompt.isEmpty) return;

    // Immediately clear the input field and update the UI.
    _textController.clear();
    FocusScope.of(context).unfocus(); // Dismiss the keyboard

    setState(() {
      // Add the user's message to the chat.
      _messages.add(ChatMessage(text: prompt, isUser: true));
      // Add an empty message for the assistant that will be updated as tokens stream in.
      _messages.add(ChatMessage(text: "", isUser: false));
      _isAssistantTyping = true;
    });
    _scrollToBottom();

    // Create generation parameters from the current settings
    final params = GenerationParams(
      temperature: _temperature,
      topK: _topK,
      topP: _topP,
      minP: _minP,
    );

    // Format the prompt using the appropriate chat template
    final formattedPrompt = _formatPrompt(prompt);

    // Stream tokens from the model with custom parameters
    final responseBuffer = StringBuffer();
    int tokenCount = 0;
    await for (final tokenPiece in _controller.runPromptStreaming(
      formattedPrompt,
      params: params,
    )) {
      tokenCount++;
      print("Received token #$tokenCount: '$tokenPiece'");
      responseBuffer.write(tokenPiece);

      // Get current text and clean it from all template tags
      String currentText = responseBuffer.toString();
      print("Current buffer: '$currentText'");

      // Check if we've hit the end-of-turn marker - stop streaming
      // Support both Gemma and Qwen formats (including malformed versions)
      if (currentText.contains('<end_of_turn>') ||
          currentText.contains('</start_of_turn>') ||
          currentText.contains('<|im_end|>') ||
          currentText.contains('|im_end|')) {
        print("End marker detected, stopping stream");
        // Extract thinking before cleaning
        final thinking = _extractThinking(currentText);

        // Clean any remaining tags
        final cleanedText = _cleanTemplateTags(currentText);
        print("Cleaned final text: '$cleanedText'");

        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: cleanedText,
            isUser: false,
            thinking: thinking,
          );
        });
        break;
      }

      // Extract thinking (if present)
      final thinking = _extractThinking(currentText);

      // Clean the text from template tags before displaying
      final cleanedText = _cleanTemplateTags(currentText);

      setState(() {
        // Update the last message with the accumulated response
        _messages[_messages.length - 1] = ChatMessage(
          text: cleanedText,
          isUser: false,
          thinking: thinking,
        );
      });
      _scrollToBottom();
    }

    print("Streaming complete. Total tokens: $tokenCount");

    // Final update with cleaned text if we have any content
    if (responseBuffer.isNotEmpty) {
      final thinking = _extractThinking(responseBuffer.toString());
      final cleanedText = _cleanTemplateTags(responseBuffer.toString());

      if (cleanedText.isNotEmpty) {
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: cleanedText,
            isUser: false,
            thinking: thinking,
          );
        });
      }
    }

    setState(() {
      _isAssistantTyping = false;
    });
    _scrollToBottom();
  }

  /// Extract thinking content from Qwen responses
  /// Returns partial thinking even if </think> tag hasn't appeared yet
  String? _extractThinking(String text) {
    if (text.contains('<think>')) {
      final thinkStart = text.indexOf('<think>');
      final thinkEnd = text.indexOf('</think>');
      if (thinkEnd != -1 && thinkEnd > thinkStart) {
        // Complete thinking block found
        final thinking = text
            .substring(thinkStart + '<think>'.length, thinkEnd)
            .trim();
        return thinking.isNotEmpty ? thinking : null;
      } else if (thinkStart != -1) {
        // Partial thinking (still streaming)
        final thinking = text.substring(thinkStart + '<think>'.length).trim();
        return thinking.isNotEmpty ? thinking : null;
      }
    }
    return null;
  }

  /// Remove all template tags from the text (supports Gemma and Qwen formats)
  /// Returns cleaned text with thinking removed
  String _cleanTemplateTags(String text) {
    String cleaned = text;

    // Remove Qwen thinking tags and content if present
    if (cleaned.contains('<think>')) {
      final thinkStart = cleaned.indexOf('<think>');
      final thinkEnd = cleaned.indexOf('</think>');
      if (thinkEnd != -1 && thinkEnd > thinkStart) {
        // Complete thinking block - remove it
        cleaned =
            cleaned.substring(0, thinkStart) +
            cleaned.substring(thinkEnd + '</think>'.length);
      } else {
        // Partial thinking (still streaming) - remove everything from <think> onwards
        cleaned = cleaned.substring(0, thinkStart);
      }
    }

    // Clean all template tags - order matters!
    cleaned = cleaned
        // Gemma tags
        .replaceAll('<start_of_turn>model\n', '')
        .replaceAll('<start_of_turn>user\n', '')
        .replaceAll('<start_of_turn>model', '')
        .replaceAll('<start_of_turn>user', '')
        .replaceAll('<start_of_turn>', '')
        .replaceAll('</start_of_turn>', '')
        .replaceAll('<end_of_turn>', '')
        .replaceAll('<start_of_image>', '')
        // Qwen tags - handle complete tags first
        .replaceAll('<|im_start|>system\n', '')
        .replaceAll('<|im_start|>user\n', '')
        .replaceAll('<|im_start|>assistant\n', '')
        .replaceAll('<|im_start|>system', '')
        .replaceAll('<|im_start|>user', '')
        .replaceAll('<|im_start|>assistant', '')
        .replaceAll('<|im_start|>', '')
        .replaceAll('<|im_end|>\n', '')
        .replaceAll('<|im_end|>', '')
        // Handle malformed/partial versions that might appear during streaming
        .replaceAll('|im_start|system\n', '')
        .replaceAll('|im_start|user\n', '')
        .replaceAll('|im_start|assistant\n', '')
        .replaceAll('|im_start|system', '')
        .replaceAll('|im_start|user', '')
        .replaceAll('|im_start|assistant', '')
        .replaceAll('|im_start|', '')
        .replaceAll('|im_end|\n', '')
        .replaceAll('|im_end|', '')
        // Clean any partial prefixes that might show
        .replaceAll('assistant:\n', '')
        .replaceAll('assistant:', '')
        .replaceAll('user:\n', '')
        .replaceAll('user:', '')
        .replaceAll('system:\n', '')
        .replaceAll('system:', '')
        // Tool tags
        .replaceAll('<tool_call>', '')
        .replaceAll('</tool_call>', '')
        .replaceAll('<tool_response>', '')
        .replaceAll('</tool_response>', '')
        // Clean any remaining think tags
        .replaceAll('<think>', '')
        .replaceAll('</think>', '');

    // Use regex to clean any remaining <| patterns at start/end
    cleaned = cleaned.replaceAll(RegExp(r'^<\|?\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\|?>?\s*$'), '');

    return cleaned.trim();
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

  void _showChangeModelDialog() async {
    // Create controllers OUTSIDE the builder to avoid recreation on rebuild
    final repoController = TextEditingController(text: _currentRepoId);
    final fileController = TextEditingController(text: _currentFileName);

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Model'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: repoController,
                  decoration: const InputDecoration(
                    labelText: 'Repository ID',
                    hintText: 'e.g., unsloth/gemma-3-270m-it-GGUF',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: fileController,
                  decoration: const InputDecoration(
                    labelText: 'Model Filename',
                    hintText: 'e.g., gemma-3-270m-it-Q8_0.gguf',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Note: The app will restart with the new model. Old model files will be kept.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, null);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newRepoId = repoController.text.trim();
                final newFileName = fileController.text.trim();

                if (newRepoId.isEmpty || newFileName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill in both fields')),
                  );
                  return;
                }

                // Return the values and close dialog
                Navigator.pop(context, {
                  'repoId': newRepoId,
                  'fileName': newFileName,
                });
              },
              child: const Text('Load Model'),
            ),
          ],
        );
      },
    );

    // Don't dispose controllers here - they're still being used during dialog close animation
    // They will be garbage collected automatically after the dialog is fully dismissed

    // If user confirmed, proceed with model change
    if (result != null && mounted) {
      // Dispose old controller first
      _controller.dispose();

      setState(() {
        // Create new controller instance
        _controller = LlamaController();
        _currentRepoId = result['repoId']!;
        _currentFileName = result['fileName']!;
        _isModelReady = false;
        _messages.clear();
      });

      // Reinitialize with new model
      _initializeLlama();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Generation Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Temperature
                    ListTile(
                      title: Text(
                        'Temperature: ${_temperature.toStringAsFixed(2)}',
                      ),
                      subtitle: Slider(
                        value: _temperature,
                        min: 0.0,
                        max: 2.0,
                        divisions: 40,
                        label: _temperature.toStringAsFixed(2),
                        onChanged: (value) {
                          setDialogState(() => _temperature = value);
                          setState(() => _temperature = value);
                        },
                      ),
                    ),
                    const Text(
                      'Higher = more random, Lower = more focused',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Top K
                    ListTile(
                      title: Text('Top K: $_topK'),
                      subtitle: Slider(
                        value: _topK.toDouble(),
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: _topK.toString(),
                        onChanged: (value) {
                          setDialogState(() => _topK = value.toInt());
                          setState(() => _topK = value.toInt());
                        },
                      ),
                    ),
                    const Text(
                      'Limits vocabulary to top K tokens',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Top P
                    ListTile(
                      title: Text('Top P: ${_topP.toStringAsFixed(2)}'),
                      subtitle: Slider(
                        value: _topP,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: _topP.toStringAsFixed(2),
                        onChanged: (value) {
                          setDialogState(() => _topP = value);
                          setState(() => _topP = value);
                        },
                      ),
                    ),
                    const Text(
                      'Nucleus sampling threshold',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Min P
                    ListTile(
                      title: Text('Min P: ${_minP.toStringAsFixed(2)}'),
                      subtitle: Slider(
                        value: _minP,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: _minP.toStringAsFixed(2),
                        onChanged: (value) {
                          setDialogState(() => _minP = value);
                          setState(() => _minP = value);
                        },
                      ),
                    ),
                    const Text(
                      'Minimum probability threshold',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Reset to defaults
                    setDialogState(() {
                      _temperature = 0.8;
                      _topK = 40;
                      _topP = 0.95;
                      _minP = 0.05;
                    });
                    setState(() {
                      _temperature = 0.8;
                      _topK = 40;
                      _topP = 0.95;
                      _minP = 0.05;
                    });
                  },
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine if the input should be enabled.
    final bool canSendMessage = _isModelReady && !_isAssistantTyping;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Llama Chat'),
            if (_isModelReady)
              Text(
                'Model: ${_modelType.toUpperCase()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
          ],
        ),
        actions: [
          // Change Model button
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _showChangeModelDialog,
            tooltip: 'Change Model',
          ),
          // Settings button
          if (_isModelReady)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsDialog,
              tooltip: 'Generation Settings',
            ),
          // Show a loading indicator in the app bar while the model is not ready.
          if (!_isModelReady)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chat messages area
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8.0),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return ChatBubble(
                    text: message.text,
                    isUser: message.isUser,
                    thinking: message.thinking,
                    // Show typing indicator on the last assistant message while typing
                    isTyping:
                        index == _messages.length - 1 &&
                        _isAssistantTyping &&
                        !message.isUser,
                  );
                },
              ),
            ),

            // Input area
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      enabled: canSendMessage,
                      decoration: InputDecoration(
                        hintText: canSendMessage
                            ? 'Type a message...'
                            : 'Waiting for response...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24.0),
                        ),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) =>
                          canSendMessage ? _handleSendPrompt() : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: canSendMessage ? _handleSendPrompt : null,
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A widget to display a chat message bubble with thinking process support
class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.thinking,
    this.isTyping = false,
  });

  final String text;
  final bool isUser;
  final String? thinking;
  final bool isTyping;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _showThinking = true; // Auto-expand thinking by default

  @override
  void didUpdateWidget(ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-expand when thinking content appears
    if (widget.thinking != null &&
        widget.thinking!.isNotEmpty &&
        oldWidget.thinking != widget.thinking) {
      setState(() {
        _showThinking = true;
      });
    }
  }

  // Strip HTML tags for clean display
  String _stripHtmlTags(String text) {
    return text
        .replaceAll(RegExp(r'<div[^>]*>'), '')
        .replaceAll('</div>', '\n')
        .replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br />', '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _stripHtmlTags(widget.text);

    return Align(
      alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: widget.isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child:
            widget.isTyping &&
                widget.text.isEmpty &&
                (widget.thinking == null || widget.thinking!.isEmpty)
            ? const SizedBox(
                width: 25,
                height: 25,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thinking section (expandable)
                  if (widget.thinking != null && widget.thinking!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _showThinking = !_showThinking;
                              });
                            },
                            child: Row(
                              children: [
                                Icon(
                                  _showThinking
                                      ? Icons.psychology
                                      : Icons.psychology_outlined,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer
                                      .withOpacity(0.7),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Thinking Process',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer
                                        .withOpacity(0.7),
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _showThinking
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer
                                      .withOpacity(0.7),
                                ),
                              ],
                            ),
                          ),
                          if (_showThinking)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: SelectableText(
                                _stripHtmlTags(widget.thinking!),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer
                                      .withOpacity(0.8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Main text content
                  // Show "..." while thinking is in progress, actual text when complete
                  if (widget.thinking != null &&
                      widget.thinking!.isNotEmpty &&
                      widget.isTyping &&
                      displayText.isEmpty)
                    // Thinking in progress with no response yet - show placeholder
                    Text(
                      '...',
                      style: TextStyle(
                        color: widget.isUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                        fontSize: 20,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (displayText.isNotEmpty)
                    // Show actual response
                    SelectableText(
                      displayText,
                      style: TextStyle(
                        color: widget.isUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                      ),
                    ),

                  // Typing indicator (only when not thinking)
                  if (widget.isTyping &&
                      widget.text.isNotEmpty &&
                      (widget.thinking == null || widget.thinking!.isEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.isUser
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
