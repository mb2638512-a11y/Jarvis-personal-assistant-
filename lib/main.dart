import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> phoneActions() async {
    if (Theme.of(context).platform != TargetPlatform.android) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone-local actions are available in the Android app.')),
      );
      return;
    }
    final urlController = TextEditingController();
    String feedback = 'These actions run on this phone, not on the remote PC.';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('This phone · local actions'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Jarvis can open Android Settings, open a secure website, and read basic device status.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'HTTPS website',
                      hintText: 'https://example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await const MethodChannel('com.jarvis.assistant/phone_actions')
                            .invokeMethod<bool>('openSettings');
                        setDialogState(() => feedback = 'Android Settings opened on this phone.');
                      } catch (error) {
                        setDialogState(() => feedback = 'Could not open Settings: $error');
                      }
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open Android Settings'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(urlController.text.trim());
                      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
                        setDialogState(() => feedback = 'Enter a valid HTTPS URL without embedded credentials.');
                        return;
                      }
                      try {
                        await const MethodChannel('com.jarvis.assistant/phone_actions')
                            .invokeMethod<bool>('openSecureUrl', {'url': uri.toString()});
                        setDialogState(() => feedback = 'Website opened on this phone.');
                      } catch (error) {
                        setDialogState(() => feedback = 'Could not open website: $error');
                      }
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Open HTTPS website'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final status = await const MethodChannel('com.jarvis.assistant/phone_actions')
                            .invokeMapMethod<String, dynamic>('getDeviceStatus');
                        setDialogState(() => feedback = status == null
                            ? 'No device status returned.'
                            : 'Device: ${status['device']} · Android ${status['android_version']} · API ${status['sdk']}');
                      } catch (error) {
                        setDialogState(() => feedback = 'Could not read device status: $error');
                      }
                    },
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Read phone status'),
                  ),
                  const SizedBox(height: 10),
                  Text(feedback, style: const TextStyle(color: Color(0xff9bacc2))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          ],
        ),
      ),
    );
    urlController.dispose();
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

  Widget _launchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool compact = false,
  }) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(compact ? 13 : 17),
          decoration: BoxDecoration(
            color: const Color(0xff101a2a),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xff24354b)),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  color: const Color(0xff15374a),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: const Color(0xff75e3ff), size: compact ? 20 : 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xff94a8c0), fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xff71869e), size: 19),
            ],
          ),
        ),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 11, top: 8),
        child: Text(text.toUpperCase(), style: const TextStyle(
          color: Color(0xff80dff7), letterSpacing: 1.7, fontSize: 10, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 980;
    final wide = width >= 650;
    final quickActions = <Widget>[
      _launchTile(icon: Icons.desktop_windows_rounded, title: 'Control your PC', subtitle: 'Run approved remote actions', onTap: remoteControl, compact: !wide),
      _launchTile(icon: Icons.phone_android_rounded, title: 'This phone', subtitle: 'Open settings and websites', onTap: phoneActions, compact: !wide),
      _launchTile(icon: Icons.hub_rounded, title: 'Connect apps', subtitle: 'Secure social account links', onTap: openSocialHub, compact: !wide),
      _launchTile(icon: Icons.account_tree_rounded, title: 'AI models', subtitle: 'Providers, routing and keys', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LlmSettingsPage())), compact: !wide),
    ];

    final tools = <Widget>[
      _launchTile(icon: Icons.health_and_safety_outlined, title: 'Wellbeing', subtitle: 'Usage and personal check-ins', compact: true,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WellbeingPage(backendUrl: baseUrl)))),
      _launchTile(icon: Icons.memory_rounded, title: 'Device health', subtitle: 'Hardware readings and security', compact: true,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceHealthPage(backendUrl: baseUrl)))),
      _launchTile(icon: Icons.settings_rounded, title: 'Settings', subtitle: 'Backend and connection', compact: true, onTap: settings),
    ];

    final chatPanel = Column(
      children: [
        if (messages.length <= 1 && !busy)
          Padding(
            padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 14, wide ? 24 : 16, 8),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(wide ? 24 : 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xff142c42), Color(0xff101827), Color(0xff101827)]),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xff29445c)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 52, height: 52,
                  decoration: BoxDecoration(color: const Color(0xff153d50), borderRadius: BorderRadius.circular(17)),
                  child: const Icon(Icons.blur_circular_rounded, color: Color(0xff7be6ff), size: 30)),
                const SizedBox(height: 18),
                Text('Your AI. Your devices. Your workflow.',
                  style: TextStyle(fontSize: wide ? 27 : 22, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -.5)),
                const SizedBox(height: 9),
                const Text('Ask Jarvis to think with you, help with work, or use the connected tools you have configured.',
                  style: TextStyle(color: Color(0xffa7b7ca), height: 1.45)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _suggestion('Help me plan my day'),
                  _suggestion('Explain this code'),
                  _suggestion('Help me debug a problem'),
                ]),
              ]),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 12, wide ? 24 : 16, 18),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return Align(
                alignment: message.user ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(maxWidth: desktop ? 680 : width * .86),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: message.user ? const Color(0xff17435b) : const Color(0xff111b2a),
                    border: Border.all(color: message.user ? const Color(0xff28627d) : const Color(0xff24354a)),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(19), topRight: const Radius.circular(19),
                      bottomLeft: Radius.circular(message.user ? 19 : 5),
                      bottomRight: Radius.circular(message.user ? 5 : 19)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!message.user)
                      const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('JARVIS',
                        style: TextStyle(color: Color(0xff78def8), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w800))),
                    SelectableText(message.text, style: const TextStyle(height: 1.45)),
                  ]),
                ),
              );
            },
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 10, wide ? 24 : 12, 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
              decoration: BoxDecoration(color: const Color(0xff111b2a),
                border: Border.all(color: const Color(0xff2a3d53)), borderRadius: BorderRadius.circular(22)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(tooltip: 'Tools', onPressed: () => showModalBottomSheet<void>(
                  context: context, backgroundColor: const Color(0xff101827),
                  builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: quickActions)))),
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xff8ea6bd))),
                Expanded(child: TextField(
                  controller: input, minLines: 1, maxLines: 5, maxLength: 12000,
                  enabled: !busy, textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'Message Jarvis…', counterText: '',
                    filled: false, border: InputBorder.none, enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
                  onSubmitted: (_) => send(),
                )),
                const SizedBox(width: 4),
                IconButton.filled(onPressed: busy ? null : send, tooltip: 'Send message',
                  icon: const Icon(Icons.arrow_upward_rounded),
                  style: IconButton.styleFrom(minimumSize: const Size(46, 46), backgroundColor: const Color(0xff63d9f5), foregroundColor: const Color(0xff07121d))),
              ]),
            ),
          ),
        ),
      ],
    );

    final sidebar = Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: const BoxDecoration(color: Color(0xff0b1220), border: Border(right: BorderSide(color: Color(0xff1e3044)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.blur_circular_rounded, color: Color(0xff75e3ff), size: 34),
          SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('JARVIS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text('PERSONAL AI', style: TextStyle(fontSize: 9, letterSpacing: 2, color: Color(0xff8ba2bb))),
          ]),
        ]),
        const SizedBox(height: 28),
        _sectionLabel('Workspace'),
        _launchTile(icon: Icons.chat_bubble_outline_rounded, title: 'AI Assistant', subtitle: 'Chat and get things done', compact: true, onTap: () {}),
        const SizedBox(height: 9),
        ...quickActions.map((e) => Padding(padding: const EdgeInsets.only(bottom: 9), child: e)),
        const SizedBox(height: 8),
        _sectionLabel('Monitor'),
        ...tools.map((e) => Padding(padding: const EdgeInsets.only(bottom: 9), child: e)),
        const Spacer(),
        Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(
          color: const Color(0xff101827), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xff24354a))),
          child: Row(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(
              color: backendOnline ? const Color(0xff65e6a5) : const Color(0xffeab85d), shape: BoxShape.circle)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(backendOnline ? 'Backend connected' : 'Backend not verified', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xff91a5bc))),
            ])),
            IconButton(tooltip: 'Check connection', onPressed: checking ? null : checkHealth, icon: const Icon(Icons.refresh, size: 18)),
          ]),
        ),
      ]),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        title: Row(children: [
          if (!desktop) const Icon(Icons.blur_circular_rounded, color: Color(0xff75e3ff)),
          if (!desktop) const SizedBox(width: 9),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desktop ? 'AI WORKSPACE' : 'JARVIS', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 16)),
            Text(backendOnline ? 'Connected · ready to assist' : 'Personal AI assistant',
              style: const TextStyle(fontSize: 11, color: Color(0xff8ea4bb), fontWeight: FontWeight.w400)),
          ]),
        ]),
        actions: [
          if (!desktop) IconButton(tooltip: 'Remote PC control', onPressed: remoteControl, icon: const Icon(Icons.desktop_windows_outlined)),
          if (!desktop) IconButton(tooltip: 'Phone actions', onPressed: phoneActions, icon: const Icon(Icons.phone_android_outlined)),
          IconButton(tooltip: 'Check connection', onPressed: checking ? null : checkHealth,
            icon: checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded)),
          if (!desktop) PopupMenuButton<String>(
            tooltip: 'More tools',
            onSelected: (value) {
              if (value == 'social') openSocialHub();
              if (value == 'wellbeing') Navigator.of(context).push(MaterialPageRoute(builder: (_) => WellbeingPage(backendUrl: baseUrl)));
              if (value == 'health') Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceHealthPage(backendUrl: baseUrl)));
              if (value == 'models') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LlmSettingsPage()));
              if (value == 'settings') settings();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'social', child: Text('Connect apps')),
              PopupMenuItem(value: 'wellbeing', child: Text('Wellbeing dashboard')),
              PopupMenuItem(value: 'health', child: Text('Device health')),
              PopupMenuItem(value: 'models', child: Text('AI model settings')),
              PopupMenuItem(value: 'settings', child: Text('Backend settings')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: Row(children: [
        if (desktop) sidebar,
        Expanded(child: Column(children: [
          Container(
            margin: EdgeInsets.fromLTRB(desktop ? 24 : 14, 12, desktop ? 24 : 14, 0),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: backendOnline ? const Color(0xff0d2a25) : const Color(0xff211d17),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: backendOnline ? const Color(0xff205344) : const Color(0xff4a3922))),
            child: Row(children: [
              Icon(backendOnline ? Icons.check_circle_outline : Icons.info_outline,
                size: 19, color: backendOnline ? const Color(0xff70e0a3) : const Color(0xfff0c36b)),
              const SizedBox(width: 10),
              Expanded(child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xffc2ceda)))),
              if (!desktop) TextButton(onPressed: settings, child: const Text('Setup')),
            ]),
          ),
          if (!desktop)
            SizedBox(height: 92, child: ListView(scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              children: quickActions.map((e) => SizedBox(width: 245, child: Padding(padding: const EdgeInsets.only(right: 9), child: e))).toList())),
          Expanded(child: chatPanel),
        ])),
      ])),
    );
  }

  Widget _suggestion(String label) => ActionChip(
    label: Text(label, style: const TextStyle(fontSize: 11)),
    backgroundColor: const Color(0xff15283a),
    side: const BorderSide(color: Color(0xff2a4a60)),
    onPressed: () { input.text = label; send(); },
  );
}
}
