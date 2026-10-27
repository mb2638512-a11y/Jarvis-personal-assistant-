import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class LlmSettingsPage extends StatefulWidget {
  const LlmSettingsPage({super.key});
  @override
  State<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends State<LlmSettingsPage> {
  static const _storage = FlutterSecureStorage();
  static const _configKey = 'jarvis.llm.providers.v1';
  final _name = TextEditingController();
  final _baseUrl = TextEditingController(text: 'https://openrouter.ai/api/v1');
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  final _headers = TextEditingController();
  final List<Map<String, dynamic>> _providers = [];
  List<String> _models = [];
  String _kind = 'OpenRouter';
  String _task = 'general';
  String _routingMode = 'automatic';
  String? _activeId;
  bool _busy = false;
  String _status = 'Add a provider, then sync its model catalogue.';
  final Map<String, String> _presets = const {
    'OpenRouter': 'https://openrouter.ai/api/v1',
    'OpenAI': 'https://api.openai.com/v1',
    'Ollama (local)': 'http://127.0.0.1:11434/v1',
    'LM Studio (local)': 'http://127.0.0.1:1234/v1',
    'Custom OpenAI-compatible': '',
  };

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() {
    _name.dispose(); _baseUrl.dispose(); _apiKey.dispose(); _model.dispose(); _headers.dispose();
    super.dispose();
  }

  Uri? _endpoint(String base, String path) {
    final parsed = Uri.tryParse(base.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        !{'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
        (parsed.scheme.toLowerCase() != 'https' &&
          !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(parsed.host))) return null;
    return parsed.replace(path: '${parsed.path.replaceAll(RegExp(r'/+$'), '')}$path', query: null, fragment: null);
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _configKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is List && mounted) {
        setState(() {
          _providers.addAll(decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
          _activeId = _providers.isEmpty ? null : _providers.first['id'] as String?;
          if (_providers.isNotEmpty) {
            final first = _providers.first;
            _model.text = first['model'] as String? ?? '';
            _task = first['task'] as String? ?? 'general';
            _routingMode = first['routingMode'] as String? ?? 'automatic';
            _models = (first['models'] as List? ?? []).whereType<String>().toList();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'Saved provider settings could not be read.');
    }
  }

  Future<void> _save() => _storage.write(key: _configKey, value: jsonEncode(_providers));

  void _preset(String? value) {
    if (value == null) return;
    setState(() { _kind = value; _baseUrl.text = _presets[value] ?? ''; if (_name.text.trim().isEmpty) _name.text = value; });
  }

  Future<void> _addProvider() async {
    final base = _baseUrl.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final key = _apiKey.text.trim();
    if (_endpoint(base, '/models') == null) {
      setState(() => _status = 'Invalid URL. HTTPS is required except localhost/LAN development endpoints.'); return;
    }
    if (key.isEmpty && !{'Ollama (local)', 'LM Studio (local)'}.contains(_kind)) {
      setState(() => _status = 'Enter an API key, or choose a local provider.'); return;
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final provider = <String, dynamic>{
      'id': id, 'name': _name.text.trim().isEmpty ? _kind : _name.text.trim(),
      'kind': _kind, 'baseUrl': base, 'model': _model.text.trim(),
      'models': <String>[], 'task': _task, 'routingMode': _routingMode, 'headers': _headers.text.trim(),
    };
    setState(() {
      _providers.add(provider); _activeId = id; _models = [];
      _status = 'Provider saved. Sync its model list next.';
    });
    await _save();
    await _storage.write(key: 'jarvis.llm.key.$id', value: key);
    _apiKey.clear();
  }

  Future<void> _testConnection() async {
    final index = _providers.indexWhere((p) => p['id'] == _activeId);
    if (index < 0) {
      setState(() => _status = 'Add or select a provider first.');
      return;
    }
    final provider = _providers[index];
    final uri = _endpoint(provider['baseUrl'] as String, '/models');
    if (uri == null) {
      setState(() => _status = 'Provider URL is invalid or insecure.');
      return;
    }
    setState(() { _busy = true; _status = 'Testing connection to ${provider['name']}…'; });
    try {
      final id = provider['id'] as String;
      final key = await _storage.read(key: 'jarvis.llm.key.$id') ?? '';
      final headers = <String, String>{'Accept': 'application/json'};
      if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';
      final custom = (provider['headers'] as String? ?? '').trim();
      if (custom.isNotEmpty) {
        final decoded = jsonDecode(custom);
        if (decoded is! Map) throw const FormatException('Custom headers must be a JSON object.');
        for (final entry in decoded.entries) {
          final name = entry.key.toString();
          if ({'authorization', 'host', 'content-length'}.contains(name.toLowerCase()) ||
              name.contains('\\r') || name.contains('\\n')) {
            throw const FormatException('Unsafe custom header name.');
          }
          headers[name] = entry.value.toString();
        }
      }
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Provider returned HTTP ${response.statusCode}.');
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['data'] is! List) {
        throw const FormatException('Connection responded, but /models format is not OpenAI-compatible.');
      }
      final count = (body['data'] as List).whereType<Map>().where((m) => m['id'] is String).length;
      if (!mounted) return;
      setState(() => _status = 'Connection successful: ${provider['name']} returned ${count} model entries.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Connection test failed: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncModels() async {
    final index = _providers.indexWhere((p) => p['id'] == _activeId);
    if (index < 0) { setState(() => _status = 'Add or select a provider first.'); return; }
    final provider = _providers[index];
    final uri = _endpoint(provider['baseUrl'] as String, '/models');
    if (uri == null) { setState(() => _status = 'Provider URL is invalid.'); return; }
    setState(() { _busy = true; _status = 'Syncing models from ${provider['name']}…'; });
    try {
      final key = await _storage.read(key: 'jarvis.llm.key.$_activeId') ?? '';
      final headers = <String, String>{'Accept': 'application/json'};
      if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';
      final custom = (provider['headers'] as String? ?? '').trim();
      if (custom.isNotEmpty) {
        final decoded = jsonDecode(custom);
        if (decoded is! Map) throw const FormatException('Custom headers must be a JSON object.');
        for (final entry in decoded.entries) {
          if ({'authorization', 'host', 'content-length'}.contains(entry.key.toString().toLowerCase()) || entry.key.toString().contains('\\r') || entry.key.toString().contains('\\n')) {
            throw const FormatException('Unsafe custom header name.');
          }
          headers[entry.key.toString()] = entry.value.toString();
        }
      }
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${response.body.length > 180 ? response.body.substring(0, 180) : response.body}');
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['data'] is! List) {
        throw const FormatException('Endpoint did not return an OpenAI-compatible /models catalogue.');
      }
      final found = (body['data'] as List).whereType<Map>().map((e) => e['id'])
        .whereType<String>().where((s) => s.trim().isNotEmpty).toSet().toList()..sort();
      if (!mounted) return;
      setState(() { _models = found; provider['models'] = found; _status = 'Synced ${found.length} model(s).'; });
      await _save();
    } catch (error) {
      if (mounted) setState(() => _status = 'Model sync failed: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  void _selectProvider(String? id) {
    if (id == null) return;
    final matches = _providers.where((p) => p['id'] == id);
    if (matches.isEmpty) return;
    final p = matches.first;
    setState(() {
      _activeId = id; _model.text = p['model'] as String? ?? '';
      _task = p['task'] as String? ?? 'general';
      _routingMode = p['routingMode'] as String? ?? 'automatic';
      _models = (p['models'] as List? ?? []).whereType<String>().toList();
      _status = 'Selected ${p['name']}. Sync to refresh its model catalogue.';
    });
  }

  Future<void> _savePreference() async {
    final index = _providers.indexWhere((p) => p['id'] == _activeId);
    if (index < 0) return;
    setState(() {
      _providers[index]['model'] = _model.text.trim();
      _providers[index]['task'] = _task;
      _providers[index]['routingMode'] = _routingMode;
      _status = 'Model and task-routing preference saved. Jarvis chat will use this configuration on the next request.';
    });
    await _save();
  }

  Future<void> _deleteProvider(String id) async {
    setState(() {
      _providers.removeWhere((p) => p['id'] == id);
      if (_activeId == id) { _activeId = _providers.isEmpty ? null : _providers.first['id'] as String?; _models = []; _model.clear(); }
      _status = 'Provider removed.';
    });
    await _storage.delete(key: 'jarvis.llm.key.$id'); await _save();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _providers.where((p) => p['id'] == _activeId);
    final active = matches.isEmpty ? null : matches.first;
    return Scaffold(
      appBar: AppBar(title: const Text('LLM Providers & Model Router')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Add OpenAI-compatible providers, routers, or local model servers. Model sync reads the standard /v1/models endpoint.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _kind, decoration: const InputDecoration(labelText: 'Provider / router'),
            items: _presets.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(), onChanged: _preset),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Display name')),
          const SizedBox(height: 10),
          TextField(controller: _baseUrl, keyboardType: TextInputType.url, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://provider.example/v1')),
          const SizedBox(height: 10),
          TextField(controller: _apiKey, obscureText: true, autocorrect: false,
            decoration: const InputDecoration(labelText: 'API key', helperText: 'Stored in device secure storage, not in plain settings.')),
          const SizedBox(height: 10),
          TextField(controller: _headers, maxLines: 2, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Optional custom headers (JSON)', hintText: '{"HTTP-Referer":"https://your-app.example"}')),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _addProvider, icon: const Icon(Icons.add), label: const Text('Save provider')),
          const Divider(height: 28),
          if (_providers.isNotEmpty) ...[
            DropdownButtonFormField<String>(value: active == null ? null : _activeId,
              decoration: const InputDecoration(labelText: 'Configured providers'),
              items: _providers.map((p) => DropdownMenuItem<String>(value: p['id'] as String, child: Text('${p['name']} · ${p['kind']}'))).toList(),
              onChanged: _selectProvider),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _testConnection,
                icon: const Icon(Icons.wifi_tethering), label: const Text('Test connection'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : _syncModels,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                label: const Text('Sync models'))),
              IconButton(tooltip: 'Delete provider', onPressed: active == null ? null : () => _deleteProvider(active['id'] as String), icon: const Icon(Icons.delete_outline)),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: _task, decoration: const InputDecoration(labelText: 'Task category'),
              items: const [
                DropdownMenuItem(value: 'general', child: Text('General')),
                DropdownMenuItem(value: 'coding', child: Text('Coding / engineering')),
                DropdownMenuItem(value: 'reasoning', child: Text('Deep reasoning')),
                DropdownMenuItem(value: 'fast', child: Text('Fast response')),
                DropdownMenuItem(value: 'low_cost', child: Text('Low cost')),
              ], onChanged: (v) => setState(() => _task = v ?? 'general')),
            const SizedBox(height: 10),
            TextField(controller: _model, decoration: InputDecoration(labelText: 'Selected model ID',
              hintText: 'Choose from synced models or type an ID',
              suffixIcon: _models.isEmpty ? null : PopupMenuButton<String>(icon: const Icon(Icons.list_alt),
                onSelected: (v) => setState(() => _model.text = v),
                itemBuilder: (_) => _models.take(100).map((m) => PopupMenuItem(value: m, child: Text(m))).toList()))),
            if (_models.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${_models.length} synced models; selector shows first 100.')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: _routingMode, decoration: const InputDecoration(labelText: 'Routing mode'),
              items: const [
                DropdownMenuItem(value: 'automatic', child: Text('Automatic by task category')),
                DropdownMenuItem(value: 'manual', child: Text('Manual provider/model')),
              ], onChanged: (v) => setState(() => _routingMode = v ?? 'automatic')),
            const SizedBox(height: 10),
            FilledButton(onPressed: _savePreference, child: const Text('Save model preference')),
          ],
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xff101827), borderRadius: BorderRadius.circular(14)), child: Text(_status)),
          const SizedBox(height: 10),
          const Text('Compatibility note: providers must expose an OpenAI-compatible /models endpoint for automatic sync. Provider-specific APIs need adapters. Jarvis uses the saved model, task category, and provider fallback for new chat requests. Provider APIs must be OpenAI-compatible.'),
        ]))),
    );
  }
}
