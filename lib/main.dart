import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'wellbeing_page.dart';
import 'device_health_page.dart';
import 'llm_settings_page.dart';
import 'llm_client.dart';

void main() => runApp(const JarvisApp());

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Jarvis',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff68dffb),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xff080d18),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xff080d18),
            surfaceTintColor: Colors.transparent,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xff101827),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xff23334a)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xff23334a)),
            ),
          ),
        ),
        home: const ChatPage(),
      );
}

class ChatMessage {
  final String text;
  final bool user;
  final DateTime createdAt;

  ChatMessage(this.text, this.user) : createdAt = DateTime.now();
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[
    ChatMessage(
      'Hello. I’m Jarvis. Set your backend URL in Settings, then check the connection to begin.',
      false,
    ),
  ];

  String baseUrl = 'http://10.0.2.2:8000';
  bool busy = false;
  bool checking = false;
  bool backendOnline = false;
  String status = 'Connection not checked';

  Uri? _endpoint(String path) {
    final parsed = Uri.tryParse(baseUrl.trim());
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
        parsed.userInfo.isNotEmpty) {
      return null;
    }
    final scheme = parsed.scheme.toLowerCase();
    final localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
    if (scheme != 'https' && !localHosts.contains(parsed.host.toLowerCase())) {
      return null;
    }
    return parsed.replace(
      path: '${parsed.path.replaceAll(RegExp(r'/+$'), '')}$path',
      query: null,
      fragment: null,
    );
  }

  Future<void> checkHealth() async {
    final uri = _endpoint('/health');
    if (uri == null) {
      setState(() {
        backendOnline = false;
        status = 'Invalid backend URL. Use an http:// or https:// URL.';
      });
      return;
    }

    setState(() {
      checking = true;
      status = 'Checking backend…';
    });
    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        backendOnline = response.statusCode >= 200 &&
            response.statusCode < 300;
        status = backendOnline
            ? 'Backend reachable · AI configuration not yet verified'
            : 'Backend returned HTTP ${response.statusCode}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        backendOnline = false;
        status = 'Cannot reach backend. Check the URL and server.';
      });
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> openSocialHub() async {
    final uri = _endpoint('/api/social/connect');
    if (uri == null) {
      setState(() => status = 'Set a valid shared backend URL in Settings first.');
      return;
    }
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        throw Exception('Backend returned an unreadable response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data is Map ? data['detail'] : null;
        throw Exception(detail?.toString() ?? 'Social workspace is not configured.');
      }
      final rawUrl = data is Map ? data['url'] : null;
      final target = rawUrl is String ? Uri.tryParse(rawUrl) : null;
      if (target == null || target.scheme != 'https' || target.host.isEmpty) {
        throw Exception('The social workspace returned an invalid secure URL.');
      }
      if (!await launchUrl(target, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open the OAuth workspace on this device.');
      }
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Social accounts: $message')),
      );
    }
  }

  Future<void> _watchRemoteTask(
    String taskId,
    String token,
    ScaffoldMessengerState messenger,
  ) async {
    final uri = _endpoint('/api/remote/tasks/$taskId');
    if (uri == null) return;
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final response = await http.get(
          uri,
          headers: {'X-Jarvis-Remote-Token': token},
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final data = jsonDecode(response.body);
        if (data is! Map) continue;
        final taskStatus = data['status']?.toString() ?? 'unknown';
        if (taskStatus == 'succeeded') {
          final result = data['result'];
          final summary = result is Map
              ? (result['hostname'] ?? result['launched'] ?? result['opened'] ?? result['saved_to'] ?? 'Action completed')
              : 'Action completed';
          messenger.showSnackBar(
            SnackBar(content: Text('Jarvis verified: $summary')),
          );
          return;
        }
        if (taskStatus == 'failed' || taskStatus == 'expired' || taskStatus == 'cancelled') {
          final detail = data['error']?.toString();
          messenger.showSnackBar(
            SnackBar(content: Text('Jarvis task $taskStatus${detail == null ? '' : ': $detail'}')),
          );
          return;
        }
      } catch (_) {
        // A temporary network interruption should not be mistaken for task success.
      }
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Task is still pending. Check that the paired device agent is running.')),
    );
  }

  Future<void> remoteControl() async {
    final messenger = ScaffoldMessenger.of(context);
    final tokenController = TextEditingController();
    final valueController = TextEditingController();
    String action = 'get_status';
    String targetPlatform = 'windows';
    bool confirmed = false;
    String? feedback;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Remote PC control'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Connect to your paired Windows agent through the shared Jarvis backend. The Windows agent must be running.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tokenController,
                    obscureText: true,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Private remote gateway token'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: targetPlatform,
                    decoration: const InputDecoration(labelText: 'Target device'),
                    items: const [
                      DropdownMenuItem(value: 'windows', child: Text('Windows PC')),
                      DropdownMenuItem(value: 'android', child: Text('Android device via authorized ADB bridge')),
                    ],
                    onChanged: (value) => setDialogState(() => targetPlatform = value ?? 'windows'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: action,
                    decoration: const InputDecoration(labelText: 'Action'),
                    items: const [
                      DropdownMenuItem(value: 'get_status', child: Text('Get PC status')),
                      DropdownMenuItem(value: 'open_url', child: Text('Open HTTPS website')),
                      DropdownMenuItem(value: 'open_app', child: Text('Open allowlisted app')),
                      DropdownMenuItem(value: 'screenshot', child: Text('Save screenshot on PC')),
                      DropdownMenuItem(value: 'type_text', child: Text('Type text (confirm required)')),
                      DropdownMenuItem(value: 'press_key', child: Text('Press safe key (confirm required)')),
                    ],
                    onChanged: (value) => setDialogState(() => action = value ?? 'get_status'),
                  ),
                  if (['open_url', 'open_app', 'type_text', 'press_key'].contains(action)) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: valueController,
                      maxLength: action == 'type_text' ? 4000 : 2048,
                      maxLines: action == 'type_text' ? 3 : 1,
                      decoration: InputDecoration(
                        labelText: action == 'open_url' ? 'HTTPS URL' :
                          action == 'open_app' ? (targetPlatform == 'windows' ? 'App: notepad, calculator, explorer, chrome, edge, firefox, settings' : 'App: chrome, settings, youtube, maps') :
                          action == 'type_text' ? 'Text to type' :
                          'Key: ENTER, ESC, TAB, CTRL+C, CTRL+V, CTRL+S, ALT+TAB, WIN',
                      ),
                    ),
                  ],
                  if (action == 'type_text' || action == 'press_key')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: confirmed,
                      onChanged: (value) => setDialogState(() => confirmed = value ?? false),
                      title: const Text('I confirm this action on my PC'),
                    ),
                  if (feedback != null) Text(feedback!, style: const TextStyle(color: Colors.orangeAccent)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
            FilledButton(
              onPressed: () async {
                final token = tokenController.text.trim();
                if (token.isEmpty) {
                  setDialogState(() => feedback = 'Enter the private gateway token.');
                  return;
                }
                if (['type_text', 'press_key'].contains(action) && !confirmed) {
                  setDialogState(() => feedback = 'Confirm typing/key action first.');
                  return;
                }
                final value = valueController.text.trim();
                final payload = <String, dynamic>{};
                if (action == 'open_url') payload['url'] = value;
                if (action == 'open_app') payload['app'] = value;
                if (action == 'type_text') payload['text'] = value;
                if (action == 'press_key') payload['key'] = value;
                final uri = _endpoint('/api/remote/tasks');
                if (uri == null) {
                  setDialogState(() => feedback = 'Set a valid backend URL in Settings.');
                  return;
                }
                try {
                  final response = await http.post(
                    uri,
                    headers: {
                      'Content-Type': 'application/json',
                      'X-Jarvis-Remote-Token': token,
                    },
                    body: jsonEncode({
                      'target_platform': targetPlatform,
                      'kind': action,
                      'payload': payload,
                      'user_confirmed': confirmed,
                    }),
                  ).timeout(const Duration(seconds: 10));
                  dynamic data;
                  try { data = jsonDecode(response.body); } on FormatException { data = {}; }
                  if (response.statusCode < 200 || response.statusCode >= 300) {
                    final detail = data is Map ? data['detail'] : null;
                    throw Exception(detail?.toString() ?? 'Request failed (HTTP ${response.statusCode}).');
                  }
                  if (!dialogContext.mounted || !mounted) return;
                  Navigator.pop(dialogContext);
                  final taskId = data is Map ? data['task_id']?.toString() : null;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Task queued: ${taskId ?? 'unknown'} · waiting for $targetPlatform agent')),
                  );
                  if (taskId != null && taskId.isNotEmpty) {
                    _watchRemoteTask(taskId, token, messenger);
                  }
                } catch (error) {
                  setDialogState(() => feedback = error.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Queue action'),
            ),
          ],
        ),
      ),
    );
    tokenController.dispose();
    valueController.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || busy) return;

    final uri = _endpoint('/api/chat');

    setState(() {
      messages.add(ChatMessage(text, true));
      input.clear();
      busy = true;
    });
    _scrollToBottom();

    try {
      // Prefer the locally configured LLM providers; use shared backend only when none are configured.
      final localReply = await LlmClient.send(text);
      if (localReply != null) {
        if (mounted) setState(() => messages.add(ChatMessage(localReply, false)));
        return;
      }
      if (uri == null) {
        throw Exception('No local LLM provider is configured and the shared backend URL is invalid. Configure a provider in LLM Settings or fix the backend URL.');
      }
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'message': text}),
          )
          .timeout(const Duration(seconds: 60));

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        throw Exception('The backend returned an unreadable response.');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data is Map ? data['detail'] : null;
        throw Exception(detail?.toString() ?? 'Request failed (HTTP ${response.statusCode}).');
      }
      if (data is! Map || data['reply'] == null) {
        throw Exception('The backend response did not include a reply.');
      }

      if (mounted) {
        setState(() => messages.add(
              ChatMessage(data['reply'].toString(), false),
            ));
      }
    } on http.ClientException {
      if (mounted) {
        setState(() => messages.add(ChatMessage(
              'Network error. Confirm that your phone/computer can reach the configured backend.',
              false,
            )));
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        setState(() => messages.add(ChatMessage('Jarvis: $message', false)));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> settings() async {
    final controller = TextEditingController(text: baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backend settings'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backend base URL',
              hintText: 'https://your-server.example',
              helperText: 'Use your server URL. Android emulator default: http://10.0.2.2:8000',
            ),
            onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save and check'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || result == null || result.isEmpty) return;
    final parsed = Uri.tryParse(result);
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
        parsed.userInfo.isNotEmpty ||
        (parsed.scheme.toLowerCase() != 'https' &&
          !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(parsed.host.toLowerCase()))) {
      setState(() => status = 'Use HTTPS for remote servers. HTTP is allowed only for localhost, 127.0.0.1, or Android emulator host 10.0.2.2.');
      return;
    }

    setState(() {
      baseUrl = result.replaceFirst(RegExp(r'/+$'), '');
      status = 'Connection not checked';
      backendOnline = false;
    });
    await checkHealth();
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.blur_circular, color: Color(0xff68dffb)),
              SizedBox(width: 10),
              Text('JARVIS', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Check backend',
              onPressed: checking ? null : checkHealth,
              icon: checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
            IconButton(
              tooltip: 'Connect social accounts (OAuth)',
              onPressed: openSocialHub,
              icon: const Icon(Icons.hub_outlined),
            ),
            IconButton(
              tooltip: 'Remote PC control',
              onPressed: remoteControl,
              icon: const Icon(Icons.desktop_windows_outlined),
            ),
            IconButton(
              tooltip: 'Usage, health and security dashboard',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WellbeingPage(backendUrl: baseUrl),
              )),
              icon: const Icon(Icons.health_and_safety_outlined),
            ),
            IconButton(
              tooltip: 'Hardware load and device security',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DeviceHealthPage(backendUrl: baseUrl),
              )),
              icon: const Icon(Icons.memory_outlined),
            ),
            IconButton(
              tooltip: 'LLM providers and model router',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LlmSettingsPage(),
              )),
              icon: const Icon(Icons.account_tree_outlined),
            ),
            IconButton(
              tooltip: 'Backend settings',
              onPressed: settings,
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xff101827),
                      border: Border.all(color: const Color(0xff23334a)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          backendOnline ? Icons.check_circle : Icons.info_outline,
                          color: backendOnline
                              ? const Color(0xff70e0a3)
                              : const Color(0xfff3bb5f),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(status)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return Align(
                          alignment: message.user
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .78,
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: message.user
                                  ? const Color(0xff16415a)
                                  : const Color(0xff101827),
                              border: Border.all(
                                color: const Color(0xff23334a),
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(message.user ? 18 : 5),
                                bottomRight: Radius.circular(message.user ? 5 : 18),
                              ),
                            ),
                            child: SelectableText(message.text),
                          ),
                        );
                      },
                    ),
                  ),
                  if (busy) const LinearProgressIndicator(minHeight: 2),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: input,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 12000,
                              enabled: !busy,
                              textInputAction: TextInputAction.newline,
                              decoration: const InputDecoration(
                                hintText: 'Message Jarvis…',
                                counterText: '',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              onSubmitted: (_) => send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Send message',
                            onPressed: busy ? null : send,
                            icon: const Icon(Icons.arrow_upward),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(52, 52),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
