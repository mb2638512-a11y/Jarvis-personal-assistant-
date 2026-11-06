import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class IntegrationSetupPage extends StatefulWidget {
  final String backendUrl;
  const IntegrationSetupPage({super.key, required this.backendUrl});
  @override
  State<IntegrationSetupPage> createState() => _IntegrationSetupPageState();
}

class _IntegrationSetupPageState extends State<IntegrationSetupPage> {
  final _postizUrl = TextEditingController(text: 'https://api.postiz.com/public/v1');
  final _postizKey = TextEditingController();
  final _artemisUrl = TextEditingController(text: 'http://127.0.0.1:8765');
  final _artemisToken = TextEditingController();
  final _artemisGoogleKey = TextEditingController();
  bool _postizConfigured = false;
  bool _artemisConfigured = false;
  bool _busy = false;
  String _status = 'Loading encrypted integration settings from this PC…';

  Uri? _uri(String path) {
    final base = Uri.tryParse(widget.backendUrl.trim());
    if (base == null || !{'localhost', '127.0.0.1'}.contains(base.host)) return null;
    return base.replace(path: path, query: null, fragment: null);
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _postizUrl.dispose(); _postizKey.dispose(); _artemisUrl.dispose(); _artemisToken.dispose(); _artemisGoogleKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uri = _uri('/api/integration-config');
    if (uri == null) return;
    setState(() { _busy = true; _status = 'Reading PC integration settings…'; });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body is! Map) {
        throw Exception(body is Map ? (body['detail'] ?? 'Could not load integration settings.') : 'Invalid response.');
      }
      final postiz = body['postiz'] is Map ? body['postiz'] as Map : {};
      final artemis = body['artemis'] is Map ? body['artemis'] as Map : {};
      if (!mounted) return;
      setState(() {
        _postizConfigured = postiz['configured'] == true;
        _artemisConfigured = artemis['configured'] == true;
        if (postiz['base_url'] is String) _postizUrl.text = postiz['base_url'] as String;
        if (artemis['base_url'] is String && (artemis['base_url'] as String).isNotEmpty) _artemisUrl.text = artemis['base_url'] as String;
        _status = 'Integration credentials are encrypted on the PC. Secret values are never sent back to this screen.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _save(String name) async {
    final isPostiz = name == 'postiz';
    final base = isPostiz ? _postizUrl.text.trim() : _artemisUrl.text.trim();
    final secret = isPostiz ? _postizKey.text.trim() : _artemisToken.text.trim();
    if (base.isEmpty || secret.isEmpty) {
      setState(() => _status = 'Enter both the service URL and its secret.');
      return;
    }
    final uri = _uri('/api/integration-config/$name');
    if (uri == null) return;
    setState(() { _busy = true; _status = 'Encrypting and saving $name credentials on this PC…'; });
    try {
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(isPostiz
          ? {'base_url': base, 'api_key': secret}
          : {'base_url': base, 'gateway_token': secret, 'google_api_key': _artemisGoogleKey.text.trim()}),
      ).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body is Map ? (body['detail'] ?? 'Could not save integration credentials.') : 'Invalid response.');
      }
      if (isPostiz) _postizKey.clear(); else _artemisToken.clear();
      await _load();
      if (mounted) setState(() => _status = name + ' credentials saved in the encrypted PC vault.');
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PC integration setup'), actions: [
      IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.sync)),
    ]),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Text(_status, style: const TextStyle(color: Color(0xffa6b8ca))),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('POSTIZ · SOCIAL PUBLISHING', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))),
              Chip(label: Text(_postizConfigured ? 'CONFIGURED' : 'NOT SET')),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _postizUrl, decoration: const InputDecoration(labelText: 'Postiz Public API base URL')),
            const SizedBox(height: 10),
            TextField(controller: _postizKey, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'Postiz API key', helperText: 'Stored encrypted on the PC. Never synced to Android.')),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _busy ? null : () => _save('postiz'), icon: const Icon(Icons.lock), label: const Text('Save Postiz credentials')),
          ]))),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('ARTEMIS · ANDROID AUTOMATION', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))),
              Chip(label: Text(_artemisConfigured ? 'CONFIGURED' : 'NOT SET')),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _artemisUrl, decoration: const InputDecoration(labelText: 'Private ARTEMIS host URL', helperText: 'Use localhost when the ARTEMIS daemon runs on this PC.')),
            const SizedBox(height: 10),
            TextField(controller: _artemisToken, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'ARTEMIS gateway token')),
            const SizedBox(height: 10),
            TextField(controller: _artemisGoogleKey, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'Google Gemini API key for ARTEMIS', helperText: 'Optional but required for the upstream default Gemini agents. Stored encrypted on the PC.')),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _busy ? null : () => _save('artemis'), icon: const Icon(Icons.lock), label: const Text('Save ARTEMIS credentials')),
          ]))),
          if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          const Padding(padding: EdgeInsets.only(top: 14), child: Text('ARTEMIS still needs its private daemon and an authorized USB/ADB Android device. Postiz needs a live workspace and connected social channels.', style: TextStyle(color: Color(0xff8295aa), fontSize: 12))),
        ]),
      ),
    ),
  );
}
