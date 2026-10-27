import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

/// Displays hardware/security snapshots reported by a paired device collector.
class DeviceHealthPage extends StatefulWidget {
  final String backendUrl;
  const DeviceHealthPage({super.key, required this.backendUrl});
  @override
  State<DeviceHealthPage> createState() => _DeviceHealthPageState();
}

class _DeviceHealthPageState extends State<DeviceHealthPage> {
  final token = TextEditingController();
  final device = TextEditingController(text: 'my-android');
  bool busy = false;
  String status = 'Local device readings work without a server. Add a token only for optional sync.';
  Map<String, dynamic>? metrics;
  Map<String, dynamic>? security;

  Uri? endpoint(String path) {
    final base = Uri.tryParse(widget.backendUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty ||
        !{'http', 'https'}.contains(base.scheme) || base.userInfo.isNotEmpty) return null;
    return base.replace(path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path', query: null, fragment: null);
  }

  Future<dynamic> get(String path) async {
    final uri = endpoint(path);
    if (uri == null) throw Exception('Invalid backend URL.');
    final response = await http.get(uri, headers: {'X-Jarvis-Gateway-Token': token.text.trim()}).timeout(const Duration(seconds: 12));
    dynamic data;
    try { data = jsonDecode(response.body); } catch (_) { data = {}; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data is Map ? (data['detail']?.toString() ?? 'HTTP ${response.statusCode}') : 'HTTP ${response.statusCode}');
    }
    return data;
  }

  Future<void> collectPhoneMetrics() async {
    if (Theme.of(context).platform != TargetPlatform.android) {
      setState(() => status = 'Use the Windows collector on PC; this button reads Android hardware.');
      return;
    }
    setState(() { busy = true; status = 'Reading phone locally…'; });
    try {
      const channel = MethodChannel('com.jarvis.assistant/device_insights');
      final raw = await channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceMetrics');
      final body = Map<String, dynamic>.from(raw ?? {});
      body['platform'] = 'android';
      body['observed_at'] = DateTime.now().toUtc().toIso8601String();
      if (!mounted) return;
      setState(() {
        metrics = body;
        security = {
          'risk_level': 'unknown',
          'firewall_enabled': null,
          'antivirus_enabled': null,
          'realtime_protection': null,
          'disk_encryption': 'Not verified by Android app',
          'os_updates': 'Not verified by Android app',
          'screen_lock': 'Not verified by Android app',
          'findings': ['Device security checks are not available from this local metrics API.'],
        };
        status = 'Local-only mode: readings stay on this device; no server is required.';
      });
      if (token.text.trim().isNotEmpty) {
        if (device.text.trim().isEmpty) throw Exception('Enter a device ID to sync.');
        final bodyForSync = Map<String, dynamic>.from(body)
          ..['device_id'] = device.text.trim();
        final uri = endpoint('/api/wellbeing/device-metrics');
        if (uri == null) throw Exception('Invalid backend URL.');
        final response = await http.post(uri,
          headers: {'Content-Type': 'application/json', 'X-Jarvis-Gateway-Token': token.text.trim()},
          body: jsonEncode(bodyForSync)).timeout(const Duration(seconds: 12));
        if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Local reading succeeded, but sync failed: HTTP ${response.statusCode}');
        if (mounted) setState(() => status = 'Local readings shown; optional shared-backend sync succeeded.');
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => status = e.message ?? 'Phone metrics failed.');
    } catch (e) {
      if (mounted) setState(() => status = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> refresh() async {
    if (token.text.trim().isEmpty || device.text.trim().isEmpty) {
      setState(() => status = 'Enter token and device ID.'); return;
    }
    setState(() { busy = true; status = 'Loading device reports…'; });
    try {
      final id = Uri.encodeQueryComponent(device.text.trim());
      final results = await Future.wait([
        get('/api/wellbeing/device-metrics?device_id=$id&limit=1'),
        get('/api/wellbeing/device-security?device_id=$id&limit=1'),
      ]);
      if (!mounted) return;
      setState(() {
        metrics = results[0]['latest'] as Map<String, dynamic>?;
        security = results[1]['latest'] as Map<String, dynamic>?;
        status = 'Loaded reports received from paired collectors. Missing values are unknown.';
      });
    } catch (e) {
      if (mounted) setState(() => status = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  String bytes(dynamic value) => value is num ? (value / 1073741824).toStringAsFixed(2) + ' GB' : 'Unknown';
  Widget tile(String label, String value, {double? percent}) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xff9bacc2), fontSize: 12)),
      const SizedBox(height: 5), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      if (percent != null) ...[const SizedBox(height: 8), LinearProgressIndicator(value: percent.clamp(0,100)/100)],
    ])),
  );

  @override
  void dispose() { token.dispose(); device.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final s = security;
    return Scaffold(
      appBar: AppBar(title: const Text('Hardware & Security')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('DEVICE INTELLIGENCE', style: TextStyle(color: Color(0xff70e4ff), letterSpacing: 2)),
        const SizedBox(height: 8),
        const Text('Monitor actual reported load', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(controller: device, decoration: const InputDecoration(labelText: 'Device ID')),
        const SizedBox(height: 8),
        TextField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'Optional sync token (leave empty for local-only mode)')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: busy ? null : refresh, icon: const Icon(Icons.cloud_sync), label: Text(busy ? 'Loading…' : 'Load shared reports (optional)')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : collectPhoneMetrics, icon: const Icon(Icons.phone_android), label: const Text('Read phone hardware metrics')),
        const SizedBox(height: 8), Text(status, style: const TextStyle(color: Color(0xff9bacc2))),
        const SizedBox(height: 14),
        if (m == null) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No local reading yet. On Android, tap Read phone hardware metrics. Shared reports are optional and require a backend.'))),
        if (m != null) ...[
          const Text('HARDWARE LOAD', style: TextStyle(color: Color(0xff70e4ff), letterSpacing: 1.5)),
          const SizedBox(height: 8),
          GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: MediaQuery.sizeOf(context).width > 650 ? 3 : 2, childAspectRatio: 1.6, children: [
            tile('CPU load', m['cpu_percent'] == null ? 'Unknown' : '${(m['cpu_percent'] as num).toStringAsFixed(1)}%', percent: (m['cpu_percent'] as num?)?.toDouble()),
            tile('RAM load', m['memory_percent'] == null ? 'Unknown' : '${(m['memory_percent'] as num).toStringAsFixed(1)}%', percent: (m['memory_percent'] as num?)?.toDouble()),
            tile('RAM used', '${bytes(m['memory_used_bytes'])} / ${bytes(m['memory_total_bytes'])}'),
            tile('Disk used', m['disk_percent'] == null ? 'Unknown' : '${(m['disk_percent'] as num).toStringAsFixed(1)}%', percent: (m['disk_percent'] as num?)?.toDouble()),
            tile('Disk free', bytes(m['disk_free_bytes'])),
            tile('Battery', m['battery_percent'] == null ? 'Not available' : '${m['battery_percent']}%', percent: (m['battery_percent'] as num?)?.toDouble()),
            tile('Network sent', bytes(m['network_sent_bytes'])),
            tile('Network received', bytes(m['network_received_bytes'])),
          ]),
          Text('Last report: ${m['observed_at'] ?? 'unknown'}', style: const TextStyle(color: Color(0xff9bacc2), fontSize: 11)),
        ],
        const SizedBox(height: 18),
        const Text('SECURITY POSTURE', style: TextStyle(color: Color(0xff70e4ff), letterSpacing: 1.5)),
        const SizedBox(height: 8),
        if (s == null) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No security report received. This page does not scan or automatically secure the device.'))),
        if (s != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reported risk: ${s['risk_level'] ?? 'unknown'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          for (final key in ['firewall_enabled','antivirus_enabled','realtime_protection','disk_encryption','os_updates','screen_lock'])
            ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(key.replaceAll('_',' ')), trailing: Text(s[key] == null ? 'Unknown' : s[key].toString(), style: const TextStyle(color: Color(0xff9bacc2)))),
          for (final finding in (s['findings'] as List? ?? [])) Text('• $finding'),
        ]))),
        const SizedBox(height: 12),
        const Text('This is monitoring, not guaranteed hacker protection. Keep OS updates, built-in antivirus/firewall, strong passwords, MFA, encryption and backups enabled. Use HTTPS and never share the gateway token.', style: TextStyle(color: Color(0xff9bacc2), fontSize: 12)),
      ]),
    );
  }
}
