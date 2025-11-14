# How to Switch to AutoFunctionChatScreen

There are 3 easy ways to add the function calling chat to your app:

## Option 1: Add a Button to Your Existing Chat (Easiest)

Add a button to your existing `ChatScreen` to open the function calling chat:

```dart
// In your ChatScreen's build method, add this to the AppBar actions:

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text('Llama Chat ($_modelType)'),
      actions: [
        // Add this button:
        IconButton(
          icon: const Icon(Icons.functions),
          tooltip: 'Open Function Calling Chat',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AutoFunctionChatWrapper(),
              ),
            );
          },
        ),
        // ... your existing actions
      ],
    ),
    // ... rest of your build
  );
}
```

## Option 2: Replace Home Screen (Main Entry Point)

Make the function calling chat the default when you open the app:

```dart
// In lib/main.dart, change this:
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
      // Change this line:
      home: const AutoFunctionChatWrapper(), // ← Was: const ChatScreen()
    );
  }
}
```

Don't forget to import:

```dart
import 'package:flutter_application_1/screens/chat_launcher_screen.dart';
```

## Option 3: Add a Launcher Screen (Recommended)

Let users choose between regular chat and function calling:

### Step 1: Update main.dart

```dart
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
      // Use the launcher as home
      home: const ChatLauncherScreen(),
      // Define routes
      routes: {
        '/regular-chat': (context) => const ChatScreen(),
        '/function-chat': (context) => const AutoFunctionChatWrapper(),
      },
    );
  }
}
```

### Step 2: Add imports at the top of main.dart

```dart
import 'package:flutter_application_1/screens/chat_launcher_screen.dart';
```

This gives you a nice menu where users can pick which chat mode they want!

## Option 4: Use Tab Bar (Advanced)

Add tabs to switch between different chat modes:

```dart
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
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Llama Chat'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.chat), text: 'Regular'),
                Tab(icon: Icon(Icons.functions), text: 'With Tools'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              ChatScreen(),
              AutoFunctionChatWrapper(),
            ],
          ),
        ),
      ),
    );
  }
}
```

## Important: Configure Model Path

Before using the function calling chat, update the model path in:

**File:** `lib/screens/chat_launcher_screen.dart`

**Line ~55:**

```dart
// TODO: Update this path to your model
final modelPath = '/path/to/your/model.gguf';
```

**Change to your actual model path:**

```dart
// Example paths:
// - From app documents: '${dir.path}/model.gguf'
// - From downloads: await _getModelPath()
// - Hardcoded: '/data/user/0/com.example.app/files/model.gguf'

// You can copy the path logic from your existing ChatScreen:
final dir = await getApplicationDocumentsDirectory();
final modelPath = '${dir.path}/your-model-name.gguf';
```

## Recommended Models for Function Calling

The function calling chat works best with these models:

✅ **Best:**

- Llama 3.1 / 3.3 (8B or 70B)
- Functionary v3.1 / v3.2
- Hermes 2 Pro / Hermes 3
- Qwen 2.5 (7B or larger)

⚠️ **Works (with grammar constraint):**

- Most instruction-tuned models
- Your current Qwen3 model should work!

❌ **Avoid:**

- Reasoning models (DeepSeek R1, QwQ)
- Base models (not instruction-tuned)

## Testing

After adding one of the options above:

1. **Hot reload** your app (or restart)
2. Navigate to the function calling chat
3. Try asking:
   - "What's 1+1?"
   - "Calculate 25 \* 48"
   - "What time is it?"

You should see the model automatically call functions and return results!

## Troubleshooting

### "Model not found" error

- Update the model path in `chat_launcher_screen.dart`
- Make sure the model file exists

### Model outputs reasoning instead of calling functions

- See `FUNCTION_CALLING_FIXES.md`
- Try lowering temperature (already set to 0.3)
- Use a recommended function-calling model

### App crashes on navigation

- Make sure you imported all required files
- Check that AutoFunctionChatScreen is available

## Quick Copy-Paste: Option 1 Implementation

Add this to your existing `_ChatScreenState` in `main.dart`:

```dart
// At the top of the file, add import:
import 'package:flutter_application_1/screens/chat_launcher_screen.dart';

// Then in your build method's AppBar actions, add:
IconButton(
  icon: const Icon(Icons.functions),
  tooltip: 'AI Assistant with Tools',
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AutoFunctionChatWrapper(),
      ),
    );
  },
),
```

That's it! You'll have a button that opens the function calling chat.
