import 'package:flutter/material.dart';

// Correct imports for FFI and Platform detection
import 'dart:io';

import 'package:flutter_application_1/chat_template.dart';
import 'package:flutter_application_1/internal/huggingface.dart';
import 'package:flutter_application_1/internal/llama_request.dart';
import 'package:flutter_application_1/lcontroller.dart';

import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

// STEP 1: DEFINE A DATA CLASS TO PASS ARGUMENTS (BEST PRACTICE)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load chat templates at startup
  await ChatTemplateManager().loadTemplates();

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
  final String? imagePath; // Optional image path

  ChatMessage({
    required this.text,
    required this.isUser,
    this.thinking,
    this.imagePath,
  });
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
  final ImagePicker _imagePicker = ImagePicker();

  // Store images to send with next message
  final List<String> _pendingImagePaths = [];

  // Generation parameters - can be adjusted by the user
  double _temperature = 0.8;
  int _topK = 40;
  double _topP = 0.95;
  double _minP = 0.05;

  // Current model configuration
  // === TEXT-ONLY MODELS (no mmproj needed) ===
  // String _currentRepoId = "unsloth/gemma-3-270m-it-GGUF";
  // String _currentFileName = "gemma-3-270m-it-Q8_0.gguf";
  // String? _currentMmprojFileName; // null for text-only models

  // === VISION MODELS (require mmproj file) ===
  // See VISION_MODELS.md for more vision model options

  // Current: Qwen3 (text-only) - fast and efficient
  // String _currentRepoId = "unsloth/Qwen3-0.6B-GGUF";
  // String _currentFileName = "Qwen3-0.6B-Q4_K_M.gguf";
  // String? _currentMmprojFileName;

  String _currentRepoId = "Qwen/Qwen3-VL-2B-Thinking-GGUF";
  String _currentFileName = "Qwen3VL-2B-Thinking-Q4_K_M.gguf";
  String? _currentMmprojFileName = "mmproj-Qwen3VL-2B-Thinking-Q8_0.gguf";

  // String _currentRepoId = "ggml-org/SmolVLM-Instruct-GGUF";
  // String _currentFileName = "SmolVLM-Instruct-Q4_K_M.gguf";
  // String? _currentMmprojFileName = "mmproj-SmolVLM-Instruct-f16.gguf";

  // String _currentRepoId = "ggml-org/SmolVLM-500M-Instruct-GGUF";
  // String _currentFileName = "SmolVLM-500M-Instruct-Q8_0.gguf";
  // String? _currentMmprojFileName = "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf";

  // String _currentRepoId = "ggml-org/gemma-3-4b-it-GGUF";
  // String _currentFileName = "gemma-3-4b-it-Q4_K_M.gguf";
  // String? _currentMmprojFileName = "mmproj-model-f16.gguf";

  // SmolVLM (500M) - Recommended starter vision model
  // String _currentRepoId = "HuggingFaceTB/SmolVLM-Instruct-GGUF";
  // String _currentFileName = "smolvlm-instruct-q4_k_m.gguf";

  // LLaVA 1.5 (7B) - Popular vision model
  // String _currentRepoId = "mys/ggml_llava-v1.5-7b";
  // String _currentFileName = "llava-v1.5-7b-Q4_K_M.gguf";

  // Chat template
  ChatTemplate? _currentTemplate;

  // Detect model type from filename
  String get _modelType {
    return _currentTemplate?.name ?? 'Unknown';
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
    // Detect and set the chat template
    _currentTemplate = ChatTemplateManager().detectTemplate(_currentFileName);

    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/$_currentFileName';
    final file = File(savePath);

    String? mmprojPath;
    bool needsDownload = !file.existsSync();

    // Check if mmproj needs to be downloaded
    bool needsMmprojDownload = false;

    // If user specified an mmproj filename, check if it exists locally
    if (_currentMmprojFileName != null && _currentMmprojFileName!.isNotEmpty) {
      final mmprojFile = File('${dir.path}/$_currentMmprojFileName');
      if (mmprojFile.existsSync()) {
        mmprojPath = mmprojFile.path;
        print("✓ Using user-specified mmproj: $_currentMmprojFileName");
      } else if (!needsDownload) {
        // Model exists but user-specified mmproj doesn't - need to download it
        needsMmprojDownload = true;
        print("⚠️  User-specified mmproj not found: $_currentMmprojFileName");
      }
    }

    // Show download dialog if needed
    if (needsDownload || needsMmprojDownload) {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _DownloadDialog(
            repoId: _currentRepoId,
            filename: _currentFileName,
            mmprojFilename: _currentMmprojFileName,
            savePath: savePath,
            onComplete: (modelPath, mmproj) {
              mmprojPath = mmproj;
            },
            needsModel: needsDownload,
            needsMmproj: needsMmprojDownload || needsDownload,
          ),
        );
      }
    } else {
      print("✓ Model file exists at: $savePath");
      print("✓ Model file size: ${await file.length()} bytes");
      if (mmprojPath != null) {
        print("✓ Multimodal projector found: $mmprojPath");
      }
    }

    // Debug logging
    print("═══════════════════════════════════════");
    print("Model initialization:");
    print("  Model path: $savePath");
    print("  Model exists: ${file.existsSync()}");
    print("  Mmproj path: ${mmprojPath ?? 'null'}");
    if (mmprojPath != null) {
      final mmprojFile = File(mmprojPath!);
      print("  Mmproj exists: ${mmprojFile.existsSync()}");
      if (mmprojFile.existsSync()) {
        print("  Mmproj size: ${mmprojFile.lengthSync()} bytes");
      }
    }
    print("═══════════════════════════════════════");

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

    await _controller.initialize(modelPath: savePath, mmprojPath: mmprojPath);

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

  /// Find existing mmproj file in the same directory as the model
  /// Formats the prompt using the current chat template
  String _formatPrompt(
    String userMessage, {
    bool hasImage = false,
    int imageCount = 0,
  }) {
    if (_currentTemplate == null) {
      // Fallback to simple format if no template available
      return userMessage;
    }
    return _currentTemplate!.formatUserMessage(
      userMessage,
      hasImage: hasImage,
      imageCount: imageCount,
    );
  }

  /// Handles sending the prompt to the Llama model.
  void _handleSendPrompt() async {
    final prompt = _textController.text.trim();
    if (prompt.isEmpty && _pendingImagePaths.isEmpty) return;

    // Copy pending images
    final imagesToSend = List<String>.from(_pendingImagePaths);

    // Immediately clear the input field and pending images
    _textController.clear();
    FocusScope.of(context).unfocus(); // Dismiss the keyboard

    setState(() {
      // Add the user's message to the chat with images if any
      _messages.add(
        ChatMessage(
          text: prompt.isEmpty
              ? "Sent ${imagesToSend.length} image(s)"
              : prompt,
          isUser: true,
          imagePath: imagesToSend.isNotEmpty ? imagesToSend.first : null,
        ),
      );

      // Add placeholder images if there are more than one
      for (int i = 1; i < imagesToSend.length; i++) {
        _messages.add(
          ChatMessage(text: "", isUser: true, imagePath: imagesToSend[i]),
        );
      }

      // Clear pending images
      _pendingImagePaths.clear();

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
    String formattedPrompt = _formatPrompt(
      prompt.isEmpty ? "Describe this image" : prompt,
      hasImage: imagesToSend.isNotEmpty,
      imageCount: imagesToSend.length,
    );

    // Stream tokens from the model with custom parameters and images
    final responseBuffer = StringBuffer();
    int tokenCount = 0;
    await for (final tokenPiece in _controller.runPromptStreaming(
      formattedPrompt,
      params: params,
      imagePaths: imagesToSend.isNotEmpty ? imagesToSend : null,
    )) {
      tokenCount++;
      print("Received token #$tokenCount: '$tokenPiece'");
      responseBuffer.write(tokenPiece);

      // Get current text
      String currentText = responseBuffer.toString();
      print("Current buffer: '$currentText'");

      // Check if we've hit a stop sequence - stop streaming
      if (_currentTemplate != null &&
          _currentTemplate!.containsStopSequence(currentText)) {
        print("Stop sequence detected, stopping stream");

        // Extract thinking before cleaning
        final thinking = _currentTemplate!.extractThinking(currentText);

        // Clean the text
        final cleanedText = _currentTemplate!.cleanResponse(currentText);
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
      final thinking = _currentTemplate?.extractThinking(currentText);

      // Clean the text from template tags before displaying
      final cleanedText =
          _currentTemplate?.cleanResponse(currentText) ?? currentText;

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
      final thinking = _currentTemplate?.extractThinking(
        responseBuffer.toString(),
      );
      final cleanedText =
          _currentTemplate?.cleanResponse(responseBuffer.toString()) ??
          responseBuffer.toString();

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

  /// Handles picking an image from gallery or camera
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _pendingImagePaths.add(image.path);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Image added! ${_pendingImagePaths.length} image(s) ready to send.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  /// Shows dialog to choose image source
  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeModelDialog() async {
    // Create controllers OUTSIDE the builder to avoid recreation on rebuild
    final repoController = TextEditingController(text: _currentRepoId);
    final fileController = TextEditingController(text: _currentFileName);
    final mmprojController = TextEditingController(
      text: _currentMmprojFileName ?? '',
    );

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
                TextField(
                  controller: mmprojController,
                  decoration: const InputDecoration(
                    labelText: 'Mmproj Filename (Optional)',
                    hintText: 'e.g., mmproj-SmolVLM-500M-Instruct-Q8_0.gguf',
                    border: OutlineInputBorder(),
                    helperText: 'Leave empty for text-only models',
                    helperMaxLines: 2,
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
                final newMmprojFileName = mmprojController.text.trim();

                if (newRepoId.isEmpty || newFileName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please fill in repository ID and model filename',
                      ),
                    ),
                  );
                  return;
                }

                // Return the values and close dialog
                Navigator.pop(context, {
                  'repoId': newRepoId,
                  'fileName': newFileName,
                  'mmprojFileName': newMmprojFileName,
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
        _currentMmprojFileName = result['mmprojFileName']!.isEmpty
            ? null
            : result['mmprojFileName'];
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
                    imagePath: message.imagePath,
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
                  // Image picker button with badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.image),
                        onPressed: canSendMessage
                            ? _showImageSourceDialog
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                          padding: const EdgeInsets.all(12),
                        ),
                        tooltip: 'Add Image',
                      ),
                      if (_pendingImagePaths.isNotEmpty)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            child: Text(
                              '${_pendingImagePaths.length}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
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
    this.imagePath,
    this.isTyping = false,
  });

  final String text;
  final bool isUser;
  final String? thinking;
  final String? imagePath;
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
                  // Image display
                  if (widget.imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(widget.imagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              padding: const EdgeInsets.all(8),
                              color: Colors.red.withOpacity(0.1),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Failed to load image',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

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

/// Dialog that shows download progress with detailed status
class _DownloadDialog extends StatefulWidget {
  final String repoId;
  final String filename;
  final String? mmprojFilename; // User-specified mmproj filename
  final String savePath;
  final Function(String modelPath, String? mmprojPath) onComplete;
  final bool needsModel;
  final bool needsMmproj;

  const _DownloadDialog({
    required this.repoId,
    required this.filename,
    this.mmprojFilename,
    required this.savePath,
    required this.onComplete,
    this.needsModel = true,
    this.needsMmproj = true,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  String _status = 'Preparing download...';
  double _progress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final result = await downloadModelWithMmproj(
        repoId: widget.repoId,
        filename: widget.filename,
        savePath: widget.savePath,
        autoDownloadMmproj: widget.needsMmproj,
        mmprojFilename:
            widget.mmprojFilename, // Pass user-specified mmproj filename
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _status = status;
              _progress = progress;
            });
          }
        },
      );

      // Call completion callback
      widget.onComplete(result['modelPath']!, result['mmprojPath']);

      // Close dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status = 'Download failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.download, size: 24),
          SizedBox(width: 12),
          Text('Downloading Model'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.filename,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          if (_error == null) ...[
            LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
            ),
            const SizedBox(height: 12),
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(1)}% complete',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Download Failed',
                          style: TextStyle(
                            color: Colors.red[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red[800],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close),
                label: const Text('Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
