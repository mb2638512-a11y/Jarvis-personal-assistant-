import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'artemis_control_page.dart';
import 'device_health_page.dart';
import 'device_pairing_page.dart';
import 'integration_setup_page.dart';
import 'main.dart' show ChatPage;
import 'model_hub_page.dart';
import 'postiz_control_page.dart';
import 'tools_page.dart';
import 'wellbeing_page.dart';
import 'windows_pairing_page.dart';

const _bg = Color(0xff06101e);
const _panel = Color(0xff0b192a);
const _panel2 = Color(0xff10243a);
const _line = Color(0xff1c3b56);
const _cyan = Color(0xff61e7ff);
const _muted = Color(0xff8ca9bd);
const _green = Color(0xff53e0ad);
const _amber = Color(0xffffc66d);

class CommandCenterPage extends StatefulWidget {
  const CommandCenterPage({super.key});

  @override
  State<CommandCenterPage> createState() => _CommandCenterPageState();
}

class _CommandCenterPageState extends State<CommandCenterPage> {
  String _backendUrl = defaultTargetPlatform == TargetPlatform.windows
      ? 'http://127.0.0.1:8000'
      : 'http://10.0.2.2:8000';
  bool _checking = false;
  bool _online = false;
  String _health = 'Not checked';
  String _provider = 'Not verified';
  String _integrations = 'Not verified';
  String _artemis = 'Not verified';
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _restoreAndCheck();
  }

  Future<void> _restoreAndCheck() async {
    final saved = await const FlutterSecureStorage().read(key: 'jarvis.shared.backend');
    if (saved != null && saved.trim().isNotEmpty) {
      _backendUrl = saved.trim().replaceFirst(RegExp(r'/+$'), '');
    }
    await _refresh();
  }

  Uri? _uri(String path) {
    final base = Uri.tryParse(_backendUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty ||
        !{'http', 'https'}.contains(base.scheme.toLowerCase()) ||
        base.userInfo.isNotEmpty) return null;
    if (base.scheme == 'http' &&
        !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host.toLowerCase())) return null;
    return base.replace(path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path',
        query: null, fragment: null);
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    final uri = _uri(path);
    if (uri == null) return null;
    try {
      final response = await http.get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 7));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : {'result': decoded};
    } catch (_) {
      return null;
    }
  }

  String _summary(Map<String, dynamic>? data, String fallback) {
    if (data == null) return fallback;
    for (final key in ['status', 'message', 'detail', 'provider_status']) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return 'Endpoint responded · inspect details in its workspace';
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    final health = await _get('/health');
    final status = health == null ? null : await _get('/status');
    final integrations = health == null ? null : await _get('/api/integrations/status');
    final artemis = health == null ? null : await _get('/api/artemis/status');
    if (!mounted) return;
    setState(() {
      _online = health != null;
      _health = health == null ? 'Backend unreachable' : _summary(health, 'Health endpoint responded');
      _provider = status == null ? 'Not verified' : _summary(status, 'Provider status endpoint responded');
      _integrations = integrations == null ? 'Not verified' : _summary(integrations, 'Integration endpoint responded');
      _artemis = artemis == null ? 'Not verified' : _summary(artemis, 'ARTEMIS endpoint responded');
      _lastChecked = DateTime.now();
      _checking = false;
    });
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _settings() async {
    final controller = TextEditingController(text: _backendUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Shared PC backend'),
        content: SizedBox(width: 420, child: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Backend URL', hintText: 'https://your-private-pc-host'),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final parsed = Uri.tryParse(result);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme) || parsed.userInfo.isNotEmpty ||
        (parsed.scheme == 'http' && !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(parsed.host))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use HTTPS for remote connections. HTTP is allowed only for localhost.')));
      return;
    }
    _backendUrl = result.replaceFirst(RegExp(r'/+$'), '');
    await const FlutterSecureStorage().write(key: 'jarvis.shared.backend', value: _backendUrl);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Row(children: [
          Icon(Icons.blur_circular_rounded, color: _cyan, size: 28),
          SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('JARVIS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
            Text('COMMAND CENTER', style: TextStyle(color: _muted, fontSize: 9, letterSpacing: 2)),
          ]),
        ]),
        actions: [
          if (MediaQuery.sizeOf(context).width > 560)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: _statusPill())),
          IconButton(tooltip: 'Refresh status', onPressed: _checking ? null : _refresh,
            icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: 'Backend settings', onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1050;
        final wide = constraints.maxWidth >= 700;
        final content = _dashboardCards(wide: wide);
        return Row(children: [
          if (desktop) _sidebar(),
          Expanded(child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 22 : 12, 12, wide ? 22 : 12, 24),
              children: [
                if (!desktop) Align(alignment: Alignment.centerLeft, child: _statusPill()),
                const SizedBox(height: 12),
                _heroCard(),
                const SizedBox(height: 12),
                content,
                const SizedBox(height: 12),
                _quickCommands(wide),
                const SizedBox(height: 14),
                Center(child: Text(
                  _lastChecked == null ? 'Live data appears only after a real backend response' :
                    'Last checked ${TimeOfDay.fromDateTime(_lastChecked!).format(context)} · metrics are not fabricated',
                  style: const TextStyle(color: _muted, fontSize: 10),
                  textAlign: TextAlign.center,
                )),
              ],
            ),
          )),
        ]);
      }),
    );
  }

  Widget _sidebar() => Container(
    width: 220,
    decoration: const BoxDecoration(color: _panel, border: Border(right: BorderSide(color: _line))),
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      _nav(Icons.dashboard_outlined, 'Command Center', () {}),
      _nav(Icons.chat_bubble_outline, 'AI Assistant', () => _open(const ChatPage())),
      _nav(Icons.hub_outlined, 'AI Models', () => _open(ModelHubPage(backendUrl: _backendUrl, readOnly: false))),
      _nav(Icons.devices_outlined, 'Device Health', () => _open(DeviceHealthPage(backendUrl: _backendUrl))),
      _nav(Icons.extension_outlined, 'Tools & Skills', () => _open(ToolsPage(backendUrl: _backendUrl))),
      _nav(Icons.memory_outlined, 'Memory & Wellbeing', () => _open(WellbeingPage(backendUrl: _backendUrl))),
      const Spacer(),
      Text(_online ? 'PC HOST ONLINE' : 'PC HOST NOT VERIFIED',
        style: TextStyle(color: _online ? _green : _amber, fontSize: 10, letterSpacing: 1.2)),
    ]),
  );

  Widget _nav(IconData icon, String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: TextButton.icon(onPressed: action, icon: Icon(icon, size: 18),
      label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      style: TextButton.styleFrom(foregroundColor: _muted, alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12))),
  );

  Widget _statusPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(color: _online ? const Color(0xff0d2a25) : const Color(0xff2a2115),
      border: Border.all(color: _online ? const Color(0xff205344) : const Color(0xff604b29)),
      borderRadius: BorderRadius.circular(30)),
    child: Text(_online ? '● SYSTEM ONLINE' : '● SYSTEM NOT VERIFIED',
      style: TextStyle(color: _online ? _green : _amber, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
  );

  Widget _heroCard() => Container(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line),
      gradient: const RadialGradient(center: Alignment.center, radius: 1.15,
        colors: [Color(0xff123c57), _panel, Color(0xff071321)]),
    ),
    child: Column(children: [
      Container(width: 142, height: 142,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _cyan.withValues(alpha: .65)),
          boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .12), blurRadius: 34, spreadRadius: 7)],
          gradient: const RadialGradient(colors: [Color(0xff16445a), Color(0xff071522)])),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('JARVIS', style: TextStyle(color: _cyan, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4)),
          SizedBox(height: 4),
          Text('AI CORE', style: TextStyle(color: Color(0xffa3edff), fontSize: 10, letterSpacing: 3)),
        ]),
      ),
      const SizedBox(height: 14),
      const Text('Your command center', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(_health, style: const TextStyle(color: _muted, fontSize: 11), textAlign: TextAlign.center),
    ]),
  );

  Widget _dashboardCards({required bool wide}) {
    final cards = [
      _infoCard(Icons.memory, 'AI CORE', _provider, _online ? _green : _amber),
      _infoCard(Icons.hub, 'INTEGRATIONS', _integrations, _muted),
      _infoCard(Icons.smartphone, 'ARTEMIS BRIDGE', _artemis, _muted),
      _infoCard(Icons.devices, 'DEVICE PAIRING', 'Pairing is managed from the device workspace', _muted),
    ];
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 900 ? 4 : box.maxWidth >= 540 ? 2 : 1;
      return GridView.count(
        crossAxisCount: columns, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: columns == 1 ? 4.2 : 1.7,
        children: cards,
      );
    });
  }

  Widget _infoCard(IconData icon, String title, String value, Color accent) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: _panel, border: Border.all(color: _line), borderRadius: BorderRadius.circular(13)),
    child: Row(children: [
      Icon(icon, color: _cyan, size: 23),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(title, style: const TextStyle(color: _muted, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600)),
      ])),
    ]),
  );

  Widget _quickCommands(bool wide) {
    final items = <(IconData, String, String, VoidCallback)>[
      (Icons.chat_rounded, 'Talk to Jarvis', 'Open AI chat', () => _open(const ChatPage())),
      (Icons.qr_code_scanner, 'Pair this device', 'Scan or display PC pairing QR', () {
        if (defaultTargetPlatform == TargetPlatform.android) {
          _open(const DevicePairingPage());
        } else {
          _open(WindowsPairingPage(backendUrl: _backendUrl));
        }
      }),
      (Icons.model_training, 'AI model hub', 'Manage PC-connected models', () => _open(ModelHubPage(backendUrl: _backendUrl, readOnly: defaultTargetPlatform == TargetPlatform.android))),
      (Icons.campaign, 'Social workspace', 'Postiz channels and drafts', () => _open(PostizControlPage(backendUrl: _backendUrl))),
      (Icons.smart_toy, 'ARTEMIS', 'Android automation bridge', () => _open(ArtemisControlPage(backendUrl: _backendUrl))),
      (Icons.tune, 'Integrations', 'Configure connected services', () => _open(IntegrationSetupPage(backendUrl: _backendUrl))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.only(bottom: 9, left: 2),
        child: Text('QUICK COMMANDS', style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w800))),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wide ? 3 : 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: wide ? 2.8 : 1.65,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return Material(
            color: _panel2, borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12), onTap: item.$4,
              child: Padding(padding: const EdgeInsets.all(11), child: Row(children: [
                Icon(item.$1, color: _cyan, size: 22), const SizedBox(width: 9),
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(item.$3, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 9)),
                ])),
              ])),
            ),
          );
        },
      ),
    ]);
  }
}
