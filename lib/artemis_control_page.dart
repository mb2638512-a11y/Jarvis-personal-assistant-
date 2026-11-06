import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ArtemisControlPage extends StatefulWidget {
  final String backendUrl;
  const ArtemisControlPage({super.key, required this.backendUrl});
  @override
  State<ArtemisControlPage> createState() => _ArtemisControlPageState();
}

class _ArtemisControlPageState extends State<ArtemisControlPage> {
  final _goal = TextEditingController();
  final _device = TextEditingController();
  String _profile = 'flash';
  bool _confirmed = false;
  bool _busy = false;
  String _status = 'Checking the PC-hosted ARTEMIS bridge…';
  String? _taskId;
  String _taskStatus = '';
  Timer? _poller;

  Uri? _url(String path) {
    final base = Uri.tryParse(widget.backendUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    if (base.scheme != 'https' && !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host)) return null;
    return base.replace(path: path, query: null, fragment: null);
  }

  Future<Map<String, String>> _headers() async {
    final token = await const FlutterSecureStorage().read(key: 'jarvis.device.token');
    if (token == null || token.isEmpty) throw Exception('Pair this Android phone with the Windows Jarvis PC first.');
    return {'X-Jarvis-Device-Token': token, 'Accept': 'application/json'};
  }

  @override
  void initState() { super.initState(); _refreshStatus(); }

  @override
  void dispose() { _poller?.cancel(); _goal.dispose(); _device.dispose(); super.dispose(); }

  Future<void> _refreshStatus() async {
    try {
      final uri = _url('/api/artemis/status');
      if (uri == null) throw Exception('The shared PC backend URL is invalid.');
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body is! Map) {
        throw Exception(body is Map ? (body['detail'] ?? 'ARTEMIS status unavailable.') : 'Invalid status response.');
      }
      final devices = body['devices'] is List ? (body['devices'] as List).length : 0;
      if (!mounted) return;
      setState(() {
        _status = body['live_connected'] == true
          ? 'ARTEMIS host connected · $devices Android device(s) detected · ready: \${body['ready'] == true}'
          : (body['note']?.toString() ?? 'ARTEMIS is not connected.');
        if (devices == 1 && body['devices'][0] is Map) {
          _device.text = (body['devices'][0]['serial'] ?? body['devices'][0]['device_serial'] ?? body['devices'][0]['id'] ?? '').toString();
        }
      });
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _submit() async {
    if (!_confirmed) {
      setState(() => _status = 'Confirm that Jarvis may operate the selected Android device.');
      return;
    }
    final goal = _goal.text.trim();
    final serial = _device.text.trim();
    if (goal.length < 5 || serial.length < 2) {
      setState(() => _status = 'Enter a clear task and the Android device serial.');
      return;
    }
    final uri = _url('/api/artemis/tasks');
    if (uri == null) return;
    setState(() { _busy = true; _status = 'Sending task to the PC-hosted ARTEMIS engine…'; });
    try {
      final headers = await _headers();
      headers['Content-Type'] = 'application/json';
      final response = await http.post(uri, headers: headers, body: jsonEncode({
        'goal': goal,
        'device_serial': serial,
        'profile': _profile,
        'user_confirmed': true,
      })).timeout(const Duration(seconds: 25));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body is! Map) {
        throw Exception(body is Map ? (body['detail'] ?? 'ARTEMIS did not accept this task.') : 'Invalid task response.');
      }
      final id = body['task_id']?.toString();
      if (id == null || id.isEmpty) throw const FormatException('ARTEMIS did not return a task ID.');
      if (!mounted) return;
      setState(() { _taskId = id; _taskStatus = body['status']?.toString() ?? 'queued'; _status = 'Task admitted by ARTEMIS. Tracking execution…'; });
      _poller?.cancel();
      _poller = Timer.periodic(const Duration(seconds: 4), (_) => _pollTask());
      await _pollTask();
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _pollTask() async {
    final id = _taskId;
    if (id == null) return;
    try {
      final uri = _url('/api/artemis/tasks/$id');
      if (uri == null) return;
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final body = jsonDecode(response.body);
      if (body is! Map || !mounted) return;
      final status = (body['status'] ?? body['state'] ?? 'running').toString();
      setState(() {
        _taskStatus = status;
        _status = 'ARTEMIS task $id · $status';
      });
      if ({'succeeded', 'success', 'completed', 'failed', 'error', 'cancelled', 'rejected'}.contains(status.toLowerCase())) {
        _poller?.cancel();
        final output = body['output'] ?? body['result'] ?? body['error'];
        if (output != null && mounted) setState(() => _status = 'ARTEMIS $status: \${output.toString()}');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ARTEMIS · Android automation'), actions: [
      IconButton(onPressed: _busy ? null : _refreshStatus, icon: const Icon(Icons.refresh)),
    ]),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xff101827), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xff29475d))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.smartphone, color: Color(0xff75e3ff)), SizedBox(width: 10), Text('PC-ORCHESTRATED · PHONE-EXECUTED', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))]),
              const SizedBox(height: 10),
              Text(_status, style: const TextStyle(color: Color(0xffa6b8ca), height: 1.45)),
              if (_taskId != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('Task ID: $_taskId · $_taskStatus')),
            ]),
          ),
          const SizedBox(height: 18),
          TextField(controller: _device, decoration: const InputDecoration(labelText: 'Android device serial', hintText: 'e.g. R58N...')),
          const SizedBox(height: 10),
          TextField(controller: _goal, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'What should ARTEMIS do?', hintText: 'Open Settings, find Battery, and report the current battery percentage.')),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'flash', label: Text('Flash'), icon: Icon(Icons.bolt)),
              ButtonSegment(value: 'pro', label: Text('Pro'), icon: Icon(Icons.verified_user)),
            ],
            selected: {_profile},
            onSelectionChanged: _busy ? null : (value) => setState(() => _profile = value.first),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _confirmed,
            onChanged: _busy ? null : (value) => setState(() => _confirmed = value ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text('I approve this automation task on my phone'),
            subtitle: const Text('ARTEMIS can navigate apps and interact with visible controls. Review sensitive actions before running.'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _submit, icon: const Icon(Icons.play_arrow), label: const Text('Run on my Android device')),
          const SizedBox(height: 10),
          const Text('This page sends tasks through the shared Jarvis PC backend. The ARTEMIS daemon and USB/ADB device connection must be running on the PC.', style: TextStyle(color: Color(0xff8295aa), fontSize: 12)),
        ]),
      ),
    ),
  );
}
