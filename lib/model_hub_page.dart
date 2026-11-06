import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ModelHubPage extends StatefulWidget {
  final String backendUrl;
  final bool readOnly;
  const ModelHubPage({super.key, required this.backendUrl, required this.readOnly});
  @override
  State<ModelHubPage> createState() => _ModelHubPageState();
}

class _ModelHubPageState extends State<ModelHubPage> {
  final _name = TextEditingController();
  final _base = TextEditingController(text: 'https://openrouter.ai/api/v1');
  final _model = TextEditingController();
  final _key = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _providers = [];
  bool _busy = false;
  String _status = 'Loading the shared PC model catalogue…';

  Uri? _uri(String path) {
    final base = Uri.tryParse(widget.backendUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    if (base.scheme != 'https' && !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host)) return null;
    return base.replace(path: path, query: null, fragment: null);
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _name.dispose(); _base.dispose(); _model.dispose(); _key.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _busy = true; _status = 'Syncing providers and model IDs from the PC…'; });
    try {
      final uri = _uri(widget.readOnly ? '/api/models/providers/catalog' : '/api/models/providers');
      if (uri == null) throw Exception('Set the shared backend URL. HTTPS is required off localhost.');
      final headers = <String, String>{};
      if (widget.readOnly) {
        final token = await const FlutterSecureStorage().read(key: 'jarvis.device.token');
        if (token == null || token.isEmpty) throw Exception('Pair this phone with the Windows Jarvis PC first.');
        headers['X-Jarvis-Device-Token'] = token;
      }
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body is! Map) {
        throw Exception(body is Map ? (body['detail'] ?? 'Model catalogue request failed.') : 'Invalid model catalogue response.');
      }
      final raw = widget.readOnly ? body['providers'] : body['providers'];
      if (raw is! List) throw const FormatException('Provider list is missing.');
      if (!mounted) return;
      setState(() {
        _providers
          ..clear()
          ..addAll(raw.whereType<Map>().map((p) => Map<String, dynamic>.from(p)));
        _status = 'Synced ${_providers.length} provider(s) from the shared PC backend. API keys stay on the PC.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _add() async {
    final uri = _uri('/api/models/providers');
    if (uri == null) return;
    final body = {
      'name': _name.text.trim(),
      'base_url': _base.text.trim(),
      'model': _model.text.trim(),
      'api_key': _key.text.trim(),
    };
    if ([body['name'], body['base_url'], body['model'], body['api_key']].any((v) => (v as String).isEmpty)) {
      setState(() => _status = 'Complete provider name, base URL, model ID and API key.');
      return;
    }
    setState(() { _busy = true; _status = 'Encrypting and saving provider on this PC…'; });
    try {
      final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data is Map ? (data['detail'] ?? 'Provider could not be saved.') : 'Invalid provider response.');
      }
      _key.clear();
      await _load();
      if (mounted) setState(() => _status = 'Provider saved in the encrypted PC vault. Its API key was not returned to this app.');
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _activate(String id) async {
    final uri = _uri('/api/models/providers/$id/activate');
    if (uri == null) return;
    setState(() { _busy = true; });
    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Could not activate provider (HTTP ${response.statusCode}).');
      await _load();
      if (mounted) setState(() => _status = 'Active provider changed on the PC. Both devices now use this shared selection.');
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _delete(String id) async {
    final uri = _uri('/api/models/providers/$id');
    if (uri == null) return;
    final response = await http.delete(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      setState(() => _status = 'Provider could not be deleted (HTTP ${response.statusCode}).');
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.readOnly ? 'Shared AI models' : 'PC model control'),
      actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.sync), tooltip: 'Sync from PC')],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xff101827),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xff29475d)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.hub_rounded, color: Color(0xff75e3ff)), SizedBox(width: 9), Text('ONE SHARED MODEL HUB', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2))]),
                const SizedBox(height: 10),
                Text(widget.readOnly ? 'Models configured on your Jarvis PC' : 'Manage provider keys and model selection on the PC', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_status, style: const TextStyle(color: Color(0xffa6b8ca), height: 1.4)),
              ]),
            ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 20),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Provider name')),
              const SizedBox(height: 9),
              TextField(controller: _base, decoration: const InputDecoration(labelText: 'OpenAI-compatible base URL')),
              const SizedBox(height: 9),
              TextField(controller: _model, decoration: const InputDecoration(labelText: 'Default model ID')),
              const SizedBox(height: 9),
              TextField(controller: _key, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'Provider API key', helperText: 'Sent to localhost and encrypted by the PC backend. Never synced to Android.')),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: _busy ? null : _add, icon: const Icon(Icons.lock), label: const Text('Save securely on PC')),
            ],
            const SizedBox(height: 20),
            const Text('CONNECTED PROVIDERS', style: TextStyle(color: Color(0xff80e2fb), fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            if (_providers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No PC providers found yet. Add one from the Windows Jarvis app.'))),
            ..._providers.map((provider) {
              final models = (provider['models'] as List? ?? []).whereType<String>().toList();
              final active = provider['active'] == true;
              final id = provider['id']?.toString() ?? '';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(provider['name']?.toString() ?? 'Provider', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                      if (active) const Chip(label: Text('ACTIVE'), avatar: Icon(Icons.check_circle, size: 16)),
                    ]),
                    Text(provider['base_url']?.toString() ?? '', style: const TextStyle(color: Color(0xff91a5ba), fontSize: 12)),
                    const SizedBox(height: 5),
                    Text('Default: ${provider['model'] ?? 'not set'} · ${models.length} models · key stored on PC', style: const TextStyle(color: Color(0xffa6b8ca))),
                    if (provider['live_verified'] == true) const Text('Provider model endpoint verified', style: TextStyle(color: Color(0xff78dfa8), fontSize: 12))
                    else if (widget.readOnly) const Text('Live model list not verified', style: TextStyle(color: Color(0xffefc477), fontSize: 12)),
                    if (models.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(models.take(20).join(' · '), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xff91a5ba))),
                    ],
                    if (!widget.readOnly) Row(children: [
                      TextButton(onPressed: _busy || active ? null : () => _activate(id), child: const Text('Make active')),
                      const Spacer(),
                      IconButton(onPressed: _busy ? null : () => _delete(id), icon: const Icon(Icons.delete_outline), tooltip: 'Delete provider'),
                    ]),
                  ]),
                ),
              );
            }),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
            if (widget.readOnly) const Padding(padding: EdgeInsets.only(top: 14), child: Text('Android is read-only for provider credentials. Add, change or remove API keys on Windows only.', style: TextStyle(color: Color(0xffa6b8ca)))),
          ],
        ),
      ),
    ),
  );
}
