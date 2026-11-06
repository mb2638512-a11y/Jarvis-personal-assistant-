import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class PostizControlPage extends StatefulWidget {
  final String backendUrl;
  const PostizControlPage({super.key, required this.backendUrl});
  @override
  State<PostizControlPage> createState() => _PostizControlPageState();
}

class _PostizControlPageState extends State<PostizControlPage> {
  final _content = TextEditingController();
  final List<Map<String, dynamic>> _channels = [];
  final List<Map<String, dynamic>> _posts = [];
  String? _selectedChannel;
  String _mode = 'draft';
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 1));
  bool _confirmPublish = false;
  bool _busy = false;
  String _status = 'Connect to the PC-hosted Postiz API to load social channels.';

  Uri? _url(String path, [Map<String, String>? query]) {
    final base = Uri.tryParse(widget.backendUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    if (base.scheme != 'https' && !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host)) return null;
    return base.replace(path: path, queryParameters: query, fragment: null);
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (defaultTargetPlatform == TargetPlatform.android) {
      final token = await const FlutterSecureStorage().read(key: 'jarvis.device.token');
      if (token == null || token.isEmpty) throw Exception('Pair this phone with the Windows Jarvis PC first.');
      headers['X-Jarvis-Device-Token'] = token;
    }
    return headers;
  }

  @override
  void initState() { super.initState(); _loadChannels(); }

  @override
  void dispose() { _content.dispose(); super.dispose(); }

  List<dynamic> _unwrapList(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      for (final key in ['integrations', 'data', 'channels', 'posts']) {
        if (body[key] is List) return body[key] as List;
      }
    }
    return const [];
  }

  Future<void> _loadChannels() async {
    final uri = _url('/api/postiz/channels');
    if (uri == null) return;
    setState(() { _busy = true; _status = 'Loading connected Postiz channels…'; });
    try {
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 25));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body is Map ? (body['detail'] ?? 'Postiz channel request failed.') : 'HTTP ' + response.statusCode.toString());
      }
      final items = _unwrapList(body);
      final channels = items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).where((item) => item['id'] != null).toList();
      if (!mounted) return;
      setState(() {
        _channels
          ..clear()
          ..addAll(channels);
        if (_channels.isNotEmpty && !_channels.any((item) => item['id'].toString() == _selectedChannel)) {
          _selectedChannel = _channels.first['id'].toString();
        }
        _status = _channels.isEmpty
          ? 'Postiz is reachable, but no connected social channels were returned.'
          : 'Loaded ' + _channels.length.toString() + ' connected social channel(s).';
      });
      await _loadPosts();
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _loadPosts() async {
    final now = DateTime.now().toUtc();
    final uri = _url('/api/postiz/posts', {
      'startDate': now.subtract(const Duration(days: 1)).toIso8601String(),
      'endDate': now.add(const Duration(days: 30)).toIso8601String(),
    });
    if (uri == null) return;
    try {
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final body = jsonDecode(response.body);
      final posts = _unwrapList(body).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      if (mounted) setState(() { _posts..clear()..addAll(posts); });
    } catch (_) {}
  }

  String _postContent(Map<String, dynamic> item) {
    final value = item['content'] ?? item['text'] ?? item['caption'] ?? item['message'];
    if (value is String) return value;
    if (item['posts'] is List && (item['posts'] as List).isNotEmpty) {
      final first = (item['posts'] as List).first;
      if (first is Map && first['value'] is List && (first['value'] as List).isNotEmpty) {
        final nested = (first['value'] as List).first;
        if (nested is Map && nested['content'] is String) return nested['content'] as String;
      }
    }
    return 'Scheduled social post';
  }

  Future<void> _pickSchedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduledAt));
    if (time == null) return;
    setState(() => _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _createPost() async {
    final text = _content.text.trim();
    if (_selectedChannel == null || text.isEmpty) {
      setState(() => _status = 'Choose a connected channel and enter post content.');
      return;
    }
    if (_mode == 'now' && !_confirmPublish) {
      setState(() => _status = 'Confirm immediate publishing before sending this post.');
      return;
    }
    if (_mode == 'schedule' && !_scheduledAt.isAfter(DateTime.now())) {
      setState(() => _status = 'Choose a future publishing time.');
      return;
    }
    final uri = _url('/api/postiz/posts');
    if (uri == null) return;
    setState(() { _busy = true; _status = 'Sending post to Postiz…'; });
    try {
      final headers = await _headers();
      headers['Content-Type'] = 'application/json';
      final response = await http.post(uri, headers: headers, body: jsonEncode({
        'type': _mode,
        if (_mode == 'schedule') 'date': _scheduledAt.toUtc().toIso8601String(),
        'shortLink': false,
        'tags': [],
        'posts': [{
          'integration': {'id': _selectedChannel},
          'value': [{'content': text, 'image': []}],
          'settings': {},
        }],
      })).timeout(const Duration(seconds: 30));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body is Map ? (body['detail'] ?? 'Postiz rejected this post.') : 'HTTP ' + response.statusCode.toString());
      }
      if (!mounted) return;
      setState(() {
        _status = _mode == 'draft' ? 'Draft created in Postiz.' : (_mode == 'schedule' ? 'Post scheduled in Postiz.' : 'Post submitted for immediate publishing.');
        _content.clear();
        _confirmPublish = false;
      });
      await _loadPosts();
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  String _channelName(Map<String, dynamic> item) =>
      (item['name'] ?? item['identifier'] ?? item['providerIdentifier'] ?? item['platform'] ?? 'Social channel').toString();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Postiz · Social publishing'), actions: [
      IconButton(onPressed: _busy ? null : _loadChannels, icon: const Icon(Icons.sync), tooltip: 'Refresh channels'),
    ]),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xff101827), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xff29475d))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.campaign_rounded, color: Color(0xff75e3ff)), SizedBox(width: 10), Text('ONE POSTIZ WORKSPACE · BOTH DEVICES', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))]),
              const SizedBox(height: 10),
              Text(_status, style: const TextStyle(color: Color(0xffa6b8ca), height: 1.45)),
            ]),
          ),
          const SizedBox(height: 18),
          if (_channels.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No channels loaded. Configure JARVIS_POSTIZ_API_KEY and JARVIS_POSTIZ_BASE_URL on the PC, then refresh.')))
          else
            DropdownButtonFormField<String>(
              value: _selectedChannel,
              decoration: const InputDecoration(labelText: 'Publish to connected channel'),
              items: _channels.map((item) => DropdownMenuItem(
                value: item['id'].toString(),
                child: Text(_channelName(item), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _busy ? null : (value) => setState(() => _selectedChannel = value),
            ),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('UPCOMING POSTS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))),
            IconButton(onPressed: _busy ? null : _loadPosts, icon: const Icon(Icons.refresh), tooltip: 'Refresh scheduled posts'),
          ]),
          if (_posts.isEmpty)
            const Text('No upcoming posts returned by Postiz.', style: TextStyle(color: Color(0xff8295aa)))
          else
            ..._posts.take(8).map((post) => Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(_postContent(post), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text((post['status'] ?? post['date'] ?? post['publishedAt'] ?? 'Postiz post').toString()),
              ),
            )),
          const SizedBox(height: 14),
          const SizedBox(height: 14),
          TextField(controller: _content, minLines: 4, maxLines: 9, decoration: const InputDecoration(labelText: 'Post content', hintText: 'Write your social post…')),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'draft', label: Text('Draft'), icon: Icon(Icons.edit_note)),
              ButtonSegment(value: 'schedule', label: Text('Schedule'), icon: Icon(Icons.schedule)),
              ButtonSegment(value: 'now', label: Text('Publish now'), icon: Icon(Icons.send)),
            ],
            selected: {_mode},
            onSelectionChanged: _busy ? null : (value) => setState(() => _mode = value.first),
          ),
          if (_mode == 'schedule') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _busy ? null : _pickSchedule, icon: const Icon(Icons.calendar_month), label: Text('Schedule: ' + _scheduledAt.toLocal().toString().substring(0, 16))),
          ],
          if (_mode == 'now')
            CheckboxListTile(
              value: _confirmPublish,
              onChanged: _busy ? null : (value) => setState(() => _confirmPublish = value ?? false),
              contentPadding: EdgeInsets.zero,
              title: const Text('I confirm immediate publishing to the selected social account'),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy || _channels.isEmpty ? null : _createPost, icon: const Icon(Icons.send_rounded), label: Text(_mode == 'draft' ? 'Create draft' : (_mode == 'schedule' ? 'Schedule post' : 'Publish now'))),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
          const Padding(padding: EdgeInsets.only(top: 16), child: Text('Postiz API credentials stay on the Jarvis PC. Android uses its paired device credential; immediate publishing requires a separate confirmation.', style: TextStyle(color: Color(0xff8295aa), fontSize: 12))),
        ]),
      ),
    ),
  );
}
