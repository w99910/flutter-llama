import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/internal/llama_service.dart';
import 'package:flutter_application_1/screens/auto_function_chat_screen.dart';
import 'package:path_provider/path_provider.dart';

/// Option 1: Simple launcher screen that lets you choose between chat types
class ChatLauncherScreen extends StatelessWidget {
  const ChatLauncherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Chat Mode')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Regular Chat
              Card(
                child: ListTile(
                  leading: const Icon(Icons.chat, size: 40),
                  title: const Text('Regular Chat'),
                  subtitle: const Text(
                    'Standard conversation with vision support',
                  ),
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/regular-chat');
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Function Calling Chat
              Card(
                child: ListTile(
                  leading: const Icon(Icons.functions, size: 40),
                  title: const Text('AI Assistant with Tools'),
                  subtitle: const Text(
                    'Automatic function calling (calculations, time, etc.)',
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/function-chat');
                  },
                ),
              ),

              const SizedBox(height: 32),

              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(height: 8),
                    Text(
                      'Function calling mode automatically executes calculations, '
                      'gets time, and generates random numbers when you ask!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blue[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Option 2: Wrapper that initializes LlamaService for AutoFunctionChatScreen
class AutoFunctionChatWrapper extends StatefulWidget {
  const AutoFunctionChatWrapper({super.key});

  @override
  State<AutoFunctionChatWrapper> createState() =>
      _AutoFunctionChatWrapperState();
}

class _AutoFunctionChatWrapperState extends State<AutoFunctionChatWrapper> {
  LlamaService? _llamaService;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeLlamaService();
  }

  Future<void> _initializeLlamaService() async {
    try {
      final llamaService = LlamaService();

      // Use the same model as main.dart
      const currentRepoId = "unsloth/Qwen3-0.6B-GGUF";
      const currentFileName = "Qwen3-0.6B-Q4_K_M.gguf";
      const String? currentMmprojFileName = null;

      // Get the model path from app documents directory
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/$currentFileName';

      // Check if model file exists
      final file = File(modelPath);
      if (!file.existsSync()) {
        setState(() {
          _error =
              'Model not found at: $modelPath\n\n'
              'Please download the model first from the regular chat screen.\n'
              'Model: $currentRepoId\n'
              'File: $currentFileName';
          _isLoading = false;
        });
        return;
      }

      // Load the model (with mmproj if specified)
      String? mmprojPath;
      if (currentMmprojFileName != null && currentMmprojFileName.isNotEmpty) {
        final mmprojFile = File('${dir.path}/$currentMmprojFileName');
        if (mmprojFile.existsSync()) {
          mmprojPath = mmprojFile.path;
        }
      }

      final success = llamaService.loadModel(modelPath, mmprojPath: mmprojPath);

      if (success) {
        setState(() {
          _llamaService = llamaService;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load model';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _llamaService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading AI model...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return AutoFunctionChatScreen(llamaService: _llamaService!);
  }
}
