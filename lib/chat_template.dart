import 'dart:convert';
import 'package:flutter/services.dart';

/// Represents a chat template with formatting rules
class ChatTemplate {
  final String name;
  final String bosToken;
  final String eosToken;
  final String systemPrefix;
  final String systemSuffix;
  final String userPrefix;
  final String userSuffix;
  final String assistantPrefix;
  final String assistantSuffix;
  final List<String> stopSequences;
  final bool addGenerationPrompt;
  final bool supportsThinking;
  final Map<String, String>? thinkingTags;

  ChatTemplate({
    required this.name,
    required this.bosToken,
    required this.eosToken,
    required this.systemPrefix,
    required this.systemSuffix,
    required this.userPrefix,
    required this.userSuffix,
    required this.assistantPrefix,
    required this.assistantSuffix,
    required this.stopSequences,
    required this.addGenerationPrompt,
    this.supportsThinking = false,
    this.thinkingTags,
  });

  factory ChatTemplate.fromJson(Map<String, dynamic> json) {
    return ChatTemplate(
      name: json['name'] as String,
      bosToken: json['bos_token'] as String? ?? '',
      eosToken: json['eos_token'] as String? ?? '',
      systemPrefix: json['system_prefix'] as String? ?? '',
      systemSuffix: json['system_suffix'] as String? ?? '',
      userPrefix: json['user_prefix'] as String,
      userSuffix: json['user_suffix'] as String,
      assistantPrefix: json['assistant_prefix'] as String,
      assistantSuffix: json['assistant_suffix'] as String,
      stopSequences:
          (json['stop_sequences'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      addGenerationPrompt: json['add_generation_prompt'] as bool? ?? true,
      supportsThinking: json['supports_thinking'] as bool? ?? false,
      thinkingTags: json['thinking_tags'] != null
          ? Map<String, String>.from(json['thinking_tags'] as Map)
          : null,
    );
  }

  /// Format a user message according to the template.
  /// Set [addGenerationPrompt] to true to add the assistant prompt prefix.
  /// [imageCount] specifies how many <image> markers to add (default 0).
  String formatUserMessage(
    String message, {
    bool hasImage = false,
    int imageCount = 0,
    String? systemMessage,
    bool addGenerationPrompt = true,
  }) {
    final buffer = StringBuffer();

    // Add system message if provided
    if (systemMessage != null && systemMessage.isNotEmpty) {
      buffer.write(systemPrefix);
      buffer.write(systemMessage.trim());
      buffer.write(systemSuffix);
    }

    // Add user message
    // For SmolVLM, adjust the prefix based on whether there's an image
    String prefix = userPrefix;
    if (name.toLowerCase().contains('vlm') && (hasImage || imageCount > 0)) {
      // Replace ': ' with ':' for SmolVLM when image is present
      prefix = prefix.replaceAll(': ', ':');
    }

    buffer.write(prefix);

    // For multimodal models, add image tokens for each image
    // The image marker should always be added when images are present
    final actualImageCount = imageCount > 0 ? imageCount : (hasImage ? 1 : 0);
    if (actualImageCount > 0) {
      for (int i = 0; i < actualImageCount; i++) {
        buffer.write('<image>');
      }
    }

    buffer.write(message.trim());
    buffer.write(userSuffix);

    // Add assistant prompt if needed
    if (addGenerationPrompt) {
      buffer.write(assistantPrefix);
    }

    return buffer.toString();
  }

  /// Check if text contains any stop sequence
  bool containsStopSequence(String text) {
    return stopSequences.any((seq) => text.contains(seq));
  }

  /// Extract thinking content from response (for models that support it)
  String? extractThinking(String text) {
    if (!supportsThinking || thinkingTags == null) return null;

    final startTag = thinkingTags!['start']!;
    final endTag = thinkingTags!['end']!;

    if (text.contains(startTag)) {
      final thinkStart = text.indexOf(startTag);
      final thinkEnd = text.indexOf(endTag);

      if (thinkEnd != -1 && thinkEnd > thinkStart) {
        // Complete thinking block found
        final thinking = text
            .substring(thinkStart + startTag.length, thinkEnd)
            .trim();
        return thinking.isNotEmpty ? thinking : null;
      } else if (thinkStart != -1) {
        // Partial thinking (still streaming)
        final thinking = text.substring(thinkStart + startTag.length).trim();
        return thinking.isNotEmpty ? thinking : null;
      }
    }
    return null;
  }

  /// Clean template tags and thinking content from text
  String cleanResponse(String text) {
    String cleaned = text;

    // Remove thinking tags and content if present
    if (supportsThinking && thinkingTags != null) {
      final startTag = thinkingTags!['start']!;
      final endTag = thinkingTags!['end']!;

      if (cleaned.contains(startTag)) {
        final thinkStart = cleaned.indexOf(startTag);
        final thinkEnd = cleaned.indexOf(endTag);

        if (thinkEnd != -1 && thinkEnd > thinkStart) {
          // Complete thinking block - remove it
          cleaned =
              cleaned.substring(0, thinkStart) +
              cleaned.substring(thinkEnd + endTag.length);
        } else {
          // Partial thinking - remove from start tag onwards
          cleaned = cleaned.substring(0, thinkStart);
        }
      }
    }

    // Clean all stop sequences
    for (final seq in stopSequences) {
      cleaned = cleaned.replaceAll(seq, '');
    }

    // Clean template tags
    cleaned = cleaned
        .replaceAll(systemPrefix, '')
        .replaceAll(systemSuffix, '')
        .replaceAll(userPrefix, '')
        .replaceAll(userSuffix, '')
        .replaceAll(assistantPrefix, '')
        .replaceAll(assistantSuffix, '')
        .replaceAll(bosToken, '')
        .replaceAll(eosToken, '');

    // Clean partial/malformed versions (handle streaming artifacts)
    // Remove common prefixes that might appear
    cleaned = cleaned
        .replaceAll('assistant:\n', '')
        .replaceAll('assistant:', '')
        .replaceAll('Assistant:\n', '')
        .replaceAll('Assistant:', '')
        .replaceAll('user:\n', '')
        .replaceAll('user:', '')
        .replaceAll('User:\n', '')
        .replaceAll('User:', '')
        .replaceAll('system:\n', '')
        .replaceAll('system:', '')
        .replaceAll('<|im_start|>', '')
        .replaceAll('<image>', '');

    return cleaned.trim();
  }
}

/// Manager for loading and accessing chat templates
class ChatTemplateManager {
  static final ChatTemplateManager _instance = ChatTemplateManager._internal();
  factory ChatTemplateManager() => _instance;
  ChatTemplateManager._internal();

  final Map<String, ChatTemplate> _templates = {};
  bool _isLoaded = false;

  /// Load templates from JSON asset file
  Future<void> loadTemplates() async {
    if (_isLoaded) return;

    try {
      final jsonString = await rootBundle.loadString(
        'assets/chat_templates.json',
      );
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      _templates.clear();
      jsonData.forEach((key, value) {
        _templates[key] = ChatTemplate.fromJson(value as Map<String, dynamic>);
      });

      _isLoaded = true;
    } catch (e) {
      print('Error loading chat templates: $e');
      rethrow;
    }
  }

  /// Get a template by key
  ChatTemplate? getTemplate(String key) {
    return _templates[key];
  }

  /// Detect template from model filename
  ChatTemplate? detectTemplate(String filename) {
    final lower = filename.toLowerCase();

    if (lower.contains('smolvlm') || lower.contains('smol-vlm')) {
      return _templates['smolvlm'];
    } else if (lower.contains('qwen')) {
      return _templates['qwen'];
    } else if (lower.contains('gemma-3') || lower.contains('gemma3')) {
      return _templates['gemma3'];
    } else if (lower.contains('gemma-2') ||
        lower.contains('gemma2') ||
        lower.contains('gemma')) {
      return _templates['gemma'];
    } else if (lower.contains('llama-3') || lower.contains('llama3')) {
      return _templates['llama3'];
    } else if (lower.contains('llama-2') || lower.contains('llama2')) {
      return _templates['llama2'];
    } else if (lower.contains('mistral')) {
      return _templates['mistral'];
    } else if (lower.contains('mixtral')) {
      return _templates['mistral']; // Mixtral uses same format as Mistral
    } else if (lower.contains('phi-3') || lower.contains('phi3')) {
      return _templates['phi3'];
    } else if (lower.contains('phi-2') || lower.contains('phi2')) {
      return _templates['phi2'];
    } else if (lower.contains('vicuna')) {
      return _templates['vicuna'];
    } else if (lower.contains('alpaca')) {
      return _templates['alpaca'];
    } else if (lower.contains('zephyr')) {
      return _templates['zephyr'];
    } else if (lower.contains('openchat')) {
      return _templates['openchat'];
    } else if (lower.contains('hermes') ||
        lower.contains('dolphin') ||
        lower.contains('orca')) {
      return _templates['chatml'];
    }

    // Default to gemma if unknown
    return _templates['gemma'];
  }

  /// Get all available template keys
  List<String> get availableTemplates => _templates.keys.toList();

  /// Get all templates
  Map<String, ChatTemplate> get templates => Map.unmodifiable(_templates);
}
