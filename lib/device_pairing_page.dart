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
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
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
    setState(() { _busy = true; _message = 'Requesting secure pairing. Approve this phone on the Windows PC…'; });
    await _scanner.stop();
    try {
      final redeemUri = host.replace(path: '/api/pairing/redeem', query: null, fragment: null);
      final response = await http.post(
        redeemUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challenge_id': challenge,
          'code': code,
          'device_label': 'Android device',
          'platform': 'android',
        }),
      ).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body is! Map ||
          body['pending_approval'] != true || body['request_id'] is! String) {
        throw Exception(body is Map ? (body['detail'] ?? 'Pairing request was rejected.') : 'Invalid pairing response.');
      }
      final requestId = body['request_id'] as String;
      final statusUri = host.replace(path: '/api/pairing/pending/status', query: null, fragment: null);
      var approved = false;
      for (var attempt = 0; attempt < 75; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final statusResponse = await http.post(
          statusUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'challenge_id': challenge, 'request_id': requestId, 'code': code}),
        ).timeout(const Duration(seconds: 10));
        final statusBody = jsonDecode(statusResponse.body);
        if (statusResponse.statusCode < 200 || statusResponse.statusCode >= 300 || statusBody is! Map) {
          throw Exception(statusBody is Map ? (statusBody['detail'] ?? 'Pairing status check failed.') : 'Invalid pairing status.');
        }
        final status = statusBody['status']?.toString();
        if (status == 'approved') { approved = true; break; }
        if (status == 'denied' || status == 'expired') throw Exception('Pairing was denied by the PC or the request expired.');
        if (mounted) setState(() => _message = 'Waiting for you to approve this Android device on the Windows Jarvis screen…');
      }
      if (!approved) throw Exception('PC approval timed out. Generate a new QR and try again.');
      if (mounted) setState(() => _message = 'Approved. Securing this phone with the shared Jarvis backend…');
      final completeUri = host.replace(path: '/api/pairing/complete', query: null, fragment: null);
      final complete = await http.post(
        completeUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'challenge_id': challenge, 'request_id': requestId, 'code': code}),
      ).timeout(const Duration(seconds: 15));
      final completed = jsonDecode(complete.body);
      if (complete.statusCode < 200 || complete.statusCode >= 300 || completed is! Map ||
          completed['device_token'] is! String) {
        throw Exception(completed is Map ? (completed['detail'] ?? 'PC approved but credential issuance failed.') : 'Invalid credential response.');
      }
      await _secure.write(key: 'jarvis.device.token', value: completed['device_token'] as String);
      await _secure.write(key: 'jarvis.shared.backend', value: host.toString().replaceFirst(RegExp(r'/+$'), ''));
      if (!mounted) return;
      setState(() { _done = true; _message = 'Phone approved and securely paired with this Jarvis PC.'; });
    } catch (error) {
      if (mounted) setState(() => _message = 'Pairing failed: ' + error.toString().replaceFirst('Exception: ', ''));
      if (mounted && !_done) await _scanner.start();
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
