import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const JarvisApp());

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Jarvis', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff68dffb), brightness: Brightness.dark), useMaterial3: true),
    home: const ChatPage(),
  );
}

class ChatMessage {
  final String text;
  final bool user;
  const ChatMessage(this.text, this.user);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[const ChatMessage('Hello. Configure your Jarvis backend in Settings to begin.', false)];
  String baseUrl = 'http://10.0.2.2:8000';
  bool busy = false;
  String status = 'Backend not checked';

  Future<void> checkHealth() async {
    try {
      final r = await http.get(Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/health')).timeout(const Duration(seconds: 8));
      setState(() => status = r.statusCode == 200 ? 'Backend online' : 'Backend returned HTTP ${r.statusCode}');
    } catch (_) { setState(() => status = 'Cannot reach backend'); }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || busy) return;
    setState(() { messages.add(ChatMessage(text, true)); input.clear(); busy = true; });
    try {
      final r = await http.post(Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': text})).timeout(const Duration(seconds: 60));
      final data = jsonDecode(r.body);
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception(data is Map ? (data['detail'] ?? 'Request failed') : 'Request failed');
      setState(() => messages.add(ChatMessage((data['reply'] ?? '').toString(), false)));
    } catch (e) {
      setState(() => messages.add(ChatMessage('Unable to contact Jarvis: $e', false)));
    } finally {
      setState(() => busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); });
    }
  }

  Future<void> settings() async {
    final controller = TextEditingController(text: baseUrl);
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Backend settings'),
      content: TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Backend base URL', hintText: 'https://your-server.example')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save'))],
    ));
    if (result != null && result.isNotEmpty) { setState(() => baseUrl = result.replaceAll(RegExp(r'/+$'), '')); await checkHealth(); }
  }

  @override
  void dispose() { input.dispose(); scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.blur_circular), SizedBox(width: 10), Text('JARVIS')]), actions: [IconButton(onPressed: checkHealth, icon: const Icon(Icons.sync)), IconButton(onPressed: settings, icon: const Icon(Icons.settings))]),
    body: Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Theme.of(context).colorScheme.surfaceContainer, child: Text(status, textAlign: TextAlign.center)),
      Expanded(child: ListView.builder(controller: scroll, padding: const EdgeInsets.all(16), itemCount: messages.length, itemBuilder: (context, i) {
        final m = messages[i]; return Align(alignment: m.user ? Alignment.centerRight : Alignment.centerLeft, child: Container(
          constraints: const BoxConstraints(maxWidth: 340), margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: m.user ? const Color(0xff16415a) : Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
          child: SelectableText(m.text)));
      })),
      if (busy) const LinearProgressIndicator(),
      SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: TextField(controller: input, minLines: 1, maxLines: 5, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Message Jarvis…', border: OutlineInputBorder()))),
        const SizedBox(width: 8), IconButton.filled(onPressed: busy ? null : send, icon: const Icon(Icons.arrow_upward))
      ])))
    ]),
  );
}
