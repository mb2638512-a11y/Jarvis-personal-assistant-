import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const bg = Color(0xFF070B14);
const panel = Color(0xFF101827);
const cyan = Color(0xFF6CEBFF);
const muted = Color(0xFF8D9BB1);

void main() => runApp(const JarvisApp());

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JARVIS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: cyan, surface: panel),
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF0D1421),
            hintStyle: const TextStyle(color: muted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFF243247))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFF243247))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: cyan)),
          ),
        ),
        home: const JarvisHome(),
      );
}

class ChatMessage {
  const ChatMessage(this.text, this.isUser);
  final String text;
  final bool isUser;
}

class JarvisHome extends StatefulWidget {
  const JarvisHome({super.key});
  @override
  State<JarvisHome> createState() => _JarvisHomeState();
}

class _JarvisHomeState extends State<JarvisHome> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  String _baseUrl = 'http://10.0.2.2:8000';
  String _status = 'Not connected';
  bool _busy = false;
  bool _started = false;
  String get _root => _baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<void> _checkHealth() async {
    setState(() => _status = 'Checking connection…');
    try {
      final response = await http.get(Uri.parse('$_root/health')).timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _status = response.statusCode == 200 ? 'System online' : 'Server unavailable');
    } catch (_) {
      if (mounted) setState(() => _status = 'Connection unavailable');
    }
  }

  Future<void> _openSettings() async {
    final controller = TextEditingController(text: _baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Connection settings'),
        content: TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Backend URL')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    final uri = Uri.tryParse(result);
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && (uri.host == '10.0.2.2' || uri.host == 'localhost' || uri.host == '127.0.0.1')))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use HTTPS, or HTTP for a local backend.')));
      return;
    }
    setState(() => _baseUrl = result.replaceAll(RegExp(r'/+$'), ''));
    await _checkHealth();
  }

  Future<void> _send([String? suggestion]) async {
    final message = (suggestion ?? _input.text).trim();
    if (message.isEmpty || _busy) return;
    setState(() {
      _started = true;
      _messages.add(ChatMessage(message, true));
      _input.clear();
      _busy = true;
    });
    _scrollToBottom();
    try {
      final response = await http.post(
        Uri.parse('$_root/api/chat'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message}),
      ).timeout(const Duration(seconds: 60));
      final data = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data is Map ? data['detail'] : null;
        throw Exception(detail ?? 'Request failed (' + response.statusCode.toString() + ')');
      }
      final reply = data is Map ? (data['reply'] ?? '').toString() : '';
      if (reply.trim().isEmpty) throw Exception('Jarvis returned an empty reply.');
      if (mounted) setState(() => _messages.add(ChatMessage(reply, false)));
    } catch (error) {
      if (mounted) {
        setState(() => _messages.add(const ChatMessage('I could not complete that request. Check the backend connection and settings, then try again.', false)));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bg, Color(0xFF0A1120), bg])),
          child: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(child: _started ? _conversation() : _welcome()),
                _composer(),
              ],
            ),
          ),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cyan.withValues(alpha: .65)),
                gradient: const RadialGradient(colors: [Color(0xFF245B78), panel]),
                boxShadow: [BoxShadow(color: cyan.withValues(alpha: .12), blurRadius: 20)],
              ),
              child: const Icon(Icons.all_inclusive, color: cyan, size: 27),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('J A R V I S', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 3)),
              SizedBox(height: 3),
              Text('PERSONAL INTELLIGENCE', style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.6)),
            ])),
            IconButton(tooltip: 'Check connection', onPressed: _checkHealth, icon: const Icon(Icons.sync_rounded, color: muted)),
            IconButton(tooltip: 'Settings', onPressed: _openSettings, icon: const Icon(Icons.tune_rounded, color: muted)),
          ],
        ),
      );

  Widget _welcome() => ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
        children: [
          const SizedBox(height: 14),
          Center(child: Container(
            width: 174, height: 174,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [cyan.withValues(alpha: .19), const Color(0xFF4659A8).withValues(alpha: .12), Colors.transparent], stops: const [0, .56, 1]),
              border: Border.all(color: cyan.withValues(alpha: .18)),
              boxShadow: [BoxShadow(color: cyan.withValues(alpha: .08), blurRadius: 36, spreadRadius: 4)],
            ),
            child: Center(child: Container(
              width: 104, height: 104,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cyan.withValues(alpha: .55)), gradient: const RadialGradient(colors: [Color(0xFF1B4561), Color(0xFF0B1322)])),
              child: const Icon(Icons.all_inclusive_rounded, color: cyan, size: 58),
            )),
          )),
          const SizedBox(height: 30),
          const Center(child: Text('YOUR INTELLIGENCE,', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 3.2, fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          const Center(child: Text('AMPLIFIED.', textAlign: TextAlign.center, style: TextStyle(fontSize: 31, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: 1.4))),
          const SizedBox(height: 13),
          const Text('Good to see you. What would you like to work on today?', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 14, height: 1.6)),
          const SizedBox(height: 25),
          _statusCard(),
          const SizedBox(height: 25),
          const Text('START WITH A TASK', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _suggestion(Icons.lightbulb_outline_rounded, 'Think through an idea', 'Help me develop an idea'),
          const SizedBox(height: 10),
          _suggestion(Icons.code_rounded, 'Build something', 'Help me plan and build a software project'),
          const SizedBox(height: 10),
          _suggestion(Icons.auto_awesome_rounded, 'Learn something new', 'Teach me a new topic step by step'),
        ],
      );

  Widget _statusCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF233248))),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _status == 'System online' ? cyan : const Color(0xFFF2B76B), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(_status, style: const TextStyle(fontSize: 12, color: muted))),
          TextButton(onPressed: _checkHealth, child: const Text('CONNECT', style: TextStyle(fontSize: 10, letterSpacing: 1))),
        ]),
      );

  Widget _suggestion(IconData icon, String title, String prompt) => Material(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : () => _send(prompt),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF202E42))),
            child: Row(children: [
              Icon(icon, color: cyan, size: 21),
              const SizedBox(width: 13),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              const Icon(Icons.arrow_outward_rounded, color: muted, size: 17),
            ]),
          ),
        ),
      );

  Widget _conversation() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        itemCount: _messages.length + (_busy ? 1 : 0),
        itemBuilder: (context, index) {
          if (_busy && index == _messages.length) {
            return const Align(alignment: Alignment.centerLeft, child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cyan)),
                SizedBox(width: 10),
                Text('JARVIS IS THINKING', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4)),
              ]),
            ));
          }
          final message = _messages[index];
          return Align(
            alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .84),
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: message.isUser ? const Color(0xFF17384B) : panel,
                borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(message.isUser ? 18 : 5), bottomRight: Radius.circular(message.isUser ? 5 : 18)),
                border: Border.all(color: message.isUser ? cyan.withValues(alpha: .22) : const Color(0xFF253247)),
              ),
              child: SelectableText(message.text, style: const TextStyle(fontSize: 14, height: 1.55)),
            ),
          );
        },
      );

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        decoration: const BoxDecoration(color: Color(0xF5070B14), border: Border(top: BorderSide(color: Color(0xFF1C293A)))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              maxLength: 12000,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'Message Jarvis…', counterText: ''),
            )),
            const SizedBox(width: 10),
            Padding(padding: const EdgeInsets.only(bottom: 2), child: SizedBox(
              width: 52, height: 52,
              child: FilledButton(
                onPressed: _busy ? null : () => _send(),
                style: FilledButton.styleFrom(backgroundColor: cyan, foregroundColor: bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)), padding: EdgeInsets.zero),
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: bg)) : const Icon(Icons.arrow_upward_rounded, size: 23),
              ),
            )),
          ]),
          const SizedBox(height: 8),
          const Text('JARVIS AI  ·  VERIFY IMPORTANT INFORMATION', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF65748B), fontSize: 9, letterSpacing: 1.1)),
        ]),
      );
}