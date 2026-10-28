import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

/// Shared-backend dashboard. Device usage must be sent by an explicitly
/// permissioned collector; this screen never invents screen-time or reel counts.
class WellbeingPage extends StatefulWidget {
  final String backendUrl;
  const WellbeingPage({super.key, required this.backendUrl});

  @override
  State<WellbeingPage> createState() => _WellbeingPageState();
}

class _WellbeingPageState extends State<WellbeingPage> {
  final token = TextEditingController();
  final device = TextEditingController(text: 'my-android');
  final sleep = TextEditingController();
  final note = TextEditingController();
  int mood = 3;
  int energy = 3;
  bool busy = false;
  String status = 'Enter the private gateway token to load your data.';
  Map<String, dynamic>? usage;
  List<dynamic> checkins = [];
  List<dynamic> securityEvents = [];

  Uri? endpoint(String path) {
    final base = Uri.tryParse(widget.backendUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty ||
        !{'http', 'https'}.contains(base.scheme.toLowerCase()) ||
        base.userInfo.isNotEmpty) {
      return null;
    }
    final scheme = base.scheme.toLowerCase();
    const localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
    if (scheme != 'https' && !localHosts.contains(base.host.toLowerCase())) {
      return null;
    }
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path',
      query: null,
      fragment: null,
    );
  }
  Map<String, String> get headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-Jarvis-Gateway-Token': token.text.trim(),
  };

  Future<dynamic> request(String path, {Map<String, dynamic>? body}) async {
    final uri = endpoint(path);
    if (uri == null) throw Exception('Invalid backend URL.');
    final response = body == null
        ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 12))
        : await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
    dynamic data;
    try { data = jsonDecode(response.body); } catch (_) { data = {}; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data is Map ? (data['detail']?.toString() ?? 'HTTP ${response.statusCode}') : 'HTTP ${response.statusCode}');
    }
    return data;
  }

  Future<void> refreshData() async {
    if (token.text.trim().isEmpty || device.text.trim().isEmpty) {
      setState(() => status = 'Enter token and device ID first.');
      return;
    }
    setState(() { busy = true; status = 'Loading private dashboard…'; });
    try {
      final id = Uri.encodeQueryComponent(device.text.trim());
      final results = await Future.wait([
        request('/api/wellbeing/usage?device_id=$id&days=7'),
        request('/api/wellbeing/checkins?device_id=$id'),
        request('/api/wellbeing/security-events?device_id=$id'),
      ]);
      if (!mounted) return;
      setState(() {
        usage = Map<String, dynamic>.from(results[0] as Map);
        checkins = (results[1]['checkins'] as List?) ?? [];
        securityEvents = (results[2]['events'] as List?) ?? [];
        status = 'Shared backend connected · data is limited to reports actually submitted by your devices.';
      });
    } catch (error) {
      if (mounted) setState(() => status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  static const deviceChannel = MethodChannel('com.jarvis.assistant/device_insights');

  Future<void> collectAndroidUsage() async {
    if (Theme.of(context).platform != TargetPlatform.android) {
      setState(() => status = 'Native Usage Access collection is available on Android only.');
      return;
    }
    if (token.text.trim().isEmpty || device.text.trim().isEmpty) {
      setState(() => status = 'Enter gateway token and device ID first.');
      return;
    }
    setState(() { busy = true; status = 'Checking Android Usage Access permission…'; });
    try {
      final allowed = await deviceChannel.invokeMethod<bool>('hasUsageAccess') ?? false;
      if (!allowed) {
        await deviceChannel.invokeMethod<bool>('openUsageAccessSettings');
        if (mounted) setState(() => status = 'Enable Usage Access for Jarvis in Android Settings, return here, then tap Collect again.');
        return;
      }
      final rows = await deviceChannel.invokeMethod<List<dynamic>>('getWeeklyAppUsage') ?? [];
      var submitted = 0;
      for (final raw in rows) {
        final item = Map<String, dynamic>.from(raw as Map);
        final seconds = (item['foreground_seconds'] as num?)?.toInt() ?? 0;
        if (seconds <= 0) continue;
        await request('/api/wellbeing/usage', body: {
          'device_id': device.text.trim(), 'platform': 'android',
          'app_id': item['app_id'], 'app_label': item['app_label'],
          'foreground_seconds': seconds,
        });
        submitted++;
      }
      await refreshData();
      if (mounted) setState(() => status = 'Submitted $submitted Android app usage summaries for the last 7 days. No individual reel counts are inferred.');
    } on PlatformException catch (error) {
      if (mounted) setState(() => status = error.message ?? 'Android usage collection failed.');
    } catch (error) {
      if (mounted) setState(() => status = error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> saveCheckin() async {
    if (busy) return;
    if (token.text.trim().isEmpty || device.text.trim().isEmpty) {
      setState(() => status = 'Enter the gateway token and device ID before saving a check-in.');
      return;
    }
    final rawSleep = sleep.text.trim();
    final hours = rawSleep.isEmpty ? null : double.tryParse(rawSleep);
    if (rawSleep.isNotEmpty && (hours == null || hours < 0 || hours > 24)) {
      setState(() => status = 'Sleep hours must be between 0 and 24.');
      return;
    }
    setState(() { busy = true; status = 'Saving private check-in…'; });
    try {
      await request('/api/wellbeing/checkins', body: {
        'device_id': device.text.trim(), 'mood': mood, 'energy': energy,
        if (hours != null) 'sleep_hours': hours,
        if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
      });
      note.clear();
      if (mounted) {
        setState(() => status = 'Check-in saved. Refresh the dashboard to load updated history.');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wellbeing check-in saved.')));
      }
    } catch (error) {
      if (mounted) setState(() => status = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    token.dispose(); device.dispose(); sleep.dispose(); note.dispose();
    super.dispose();
  }

  Widget field(TextEditingController controller, String label, {bool secret = false}) =>
      TextField(controller: controller, obscureText: secret, decoration: InputDecoration(labelText: label));

  @override
  Widget build(BuildContext context) {
    final apps = (usage?['apps'] as List?) ?? [];
    final totalSeconds = (usage?['total_foreground_seconds'] as num?)?.toInt() ?? 0;
    String duration(int seconds) {
      final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Usage, Health & Security')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xff15354a), Color(0xff101827), Color(0xff101827)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xff29475d)),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.insights_rounded, color: Color(0xff75e3ff), size: 27),
              SizedBox(width: 10),
              Text('PERSONAL INSIGHTS', style: TextStyle(color: Color(0xff80e2fb),
                letterSpacing: 1.8, fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
            SizedBox(height: 12),
            Text('Build healthier digital habits.',
              style: TextStyle(fontSize: 25, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            SizedBox(height: 8),
            Text('A private view of reported app usage, personal check-ins and security events—without inventing missing data.',
              style: TextStyle(color: Color(0xffa6b8ca), height: 1.45)),
          ]),
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        field(device, 'Device ID (same ID used by your collector)'),
        const SizedBox(height: 10),
        field(token, 'Private JARVIS_REMOTE_GATEWAY_TOKEN', secret: true),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: busy ? null : refreshData, icon: const Icon(Icons.sync), label: Text(busy ? 'Loading…' : 'Load shared data')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : collectAndroidUsage, icon: const Icon(Icons.phone_android), label: const Text('Collect Android app usage (7 days)')),
        const SizedBox(height: 10),
        Text(status, style: const TextStyle(color: Color(0xff9bacc2))),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('APP USAGE · LAST 7 DAYS', style: TextStyle(color: Color(0xff70e4ff), fontSize: 11, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(duration(totalSeconds), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const Text('Total reported foreground time across apps'),
          const SizedBox(height: 12),
          if (apps.isEmpty) const Text('No usage records yet. A permissioned Android/Windows collector must send them first.')
          else ...apps.map((raw) {
            final app = Map<String, dynamic>.from(raw as Map);
            final seconds = (app['seconds'] as num?)?.toInt() ?? 0;
            return ListTile(contentPadding: EdgeInsets.zero, title: Text(app['app_label']?.toString() ?? app['app_id'].toString()), subtitle: Text(app['platform'].toString()), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(duration(seconds)),
              if (app['reels_count'] != null) Text('${app['reels_count']} reels*', style: const TextStyle(fontSize: 11)),
            ]));
          }),
          const SizedBox(height: 6),
          const Text('*Reel count appears only when a trusted client can genuinely report it; it is not inferred from screen time.', style: TextStyle(fontSize: 11)),
        ]))),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('HEALTH & WELLBEING CHECK-IN', style: TextStyle(color: Color(0xff70e4ff), fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Text('Mood: $mood / 5'),
          Slider(value: mood.toDouble(), min: 1, max: 5, divisions: 4, label: '$mood', onChanged: (v) => setState(() => mood = v.round())),
          Text('Energy: $energy / 5'),
          Slider(value: energy.toDouble(), min: 1, max: 5, divisions: 4, label: '$energy', onChanged: (v) => setState(() => energy = v.round())),
          field(sleep, 'Sleep hours (optional)'),
          const SizedBox(height: 10),
          field(note, 'Private note (optional)'),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : saveCheckin, child: const Text('Save check-in')),
          const SizedBox(height: 8),
          const Text('Journaling only—not diagnosis, medical monitoring, or emergency care.', style: TextStyle(fontSize: 11)),
          const Divider(height: 24),
          Text('Recent check-ins: ${checkins.length}'),
          ...checkins.take(5).map((e) => Text('Mood ${e['mood'] ?? '—'} · Energy ${e['energy'] ?? '—'} · ${e['created_at'] ?? ''}', style: const TextStyle(fontSize: 12))),
        ]))),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SECURITY EVENT JOURNAL', style: TextStyle(color: Color(0xff70e4ff), fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          const Text('Shows events reported by connected clients; it does not mean Jarvis has scanned the device or can detect every threat.'),
          const SizedBox(height: 10),
          if (securityEvents.isEmpty) const Text('No security events reported.')
          else ...securityEvents.take(15).map((e) => ListTile(contentPadding: EdgeInsets.zero, title: Text('${e['severity']} · ${e['category']}'), subtitle: Text('${e['summary']}\n${e['created_at']}'))),
        ]))),
      ]))),
    );
  }
}
