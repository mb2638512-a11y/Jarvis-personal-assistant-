import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

class DevicePairingPage extends StatefulWidget {
  const DevicePairingPage({super.key});
  @override
  State<DevicePairingPage> createState() => _DevicePairingPageState();
}

class _DevicePairingPageState extends State<DevicePairingPage> {
  static const _secure = FlutterSecureStorage();
  final _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _busy = false;
  bool _done = false;
  String _message = 'Scan the short-lived QR displayed by Jarvis on your Windows PC.';

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _done) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'jarvis' || uri.host != 'pair') {
      setState(() => _message = 'This is not a Jarvis pairing QR.');
      return;
    }
    final hostValue = uri.queryParameters['host'];
    final challenge = uri.queryParameters['challenge'];
    final code = uri.queryParameters['code'];
    final host = hostValue == null ? null : Uri.tryParse(hostValue);
    if (host == null || !host.hasScheme || host.host.isEmpty ||
        challenge == null || code == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _message = 'Pairing QR is incomplete or invalid.');
      return;
    }
    if (host.scheme != 'https' && !{'localhost', '127.0.0.1'}.contains(host.host)) {
      setState(() => _message = 'For LAN pairing, use HTTPS or a trusted private VPN tunnel. Plain HTTP is blocked.');
      return;
    }
    setState(() { _busy = true; _message = 'Confirming one-time pairing with your Jarvis PC…'; });
    try {
      final response = await http.post(
        host.replace(path: '/api/pairing/redeem', query: null, fragment: null),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challenge_id': challenge,
          'code': code,
          'device_label': 'Android device',
          'platform': 'android',
        }),
      ).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body is! Map || body['device_token'] is! String) {
        throw Exception(body is Map ? (body['detail'] ?? 'Pairing was rejected.') : 'Invalid pairing response.');
      }
      await _secure.write(key: 'jarvis.device.token', value: body['device_token'] as String);
      await _secure.write(key: 'jarvis.shared.backend', value: host.toString().replaceFirst(RegExp(r'/+$'), ''));
      if (!mounted) return;
      setState(() { _done = true; _message = 'Phone paired securely with this Jarvis PC. You can now use the shared backend.'; });
      await _scanner.stop();
    } catch (error) {
      if (mounted) setState(() => _message = 'Pairing failed: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pair Android with Jarvis PC')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(_message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _done
                ? const Center(child: Icon(Icons.verified_rounded, size: 84, color: Colors.green))
                : MobileScanner(controller: _scanner, onDetect: _onDetect),
            ),
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_done) FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}
