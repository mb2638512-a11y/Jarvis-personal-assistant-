import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

class WindowsPairingPage extends StatefulWidget {
  final String backendUrl;
  const WindowsPairingPage({super.key, required this.backendUrl});
  @override
  State<WindowsPairingPage> createState() => _WindowsPairingPageState();
}

class _WindowsPairingPageState extends State<WindowsPairingPage> {
  String? _qr;
  String _code = '';
  String _status = 'Generate a one-time QR code for your Android phone.';
  DateTime? _expiresAt;
  bool _busy = false;
  Timer? _timer;
  int _secondsLeft = 0;

  Uri? get _endpoint {
    final parsed = Uri.tryParse(widget.backendUrl.trim());
    if (parsed == null || parsed.host.isEmpty ||
        !{'localhost', '127.0.0.1'}.contains(parsed.host) ||
        parsed.scheme != 'http') return null;
    return parsed.replace(path: '/api/pairing/challenge', query: null, fragment: null);
  }

  Future<void> _generate() async {
    final uri = _endpoint;
    if (uri == null) {
      setState(() => _status = 'Open this page in the Windows Jarvis app with its local backend running.');
      return;
    }
    setState(() { _busy = true; _status = 'Generating secure one-time pairing QR…'; });
    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body is! Map) {
        final detail = body is Map ? body['detail'] : null;
        throw Exception(detail?.toString() ?? 'Pairing challenge could not be created.');
      }
      final qr = body['pairing_uri'];
      final code = body['code'];
      final expires = body['expires_in_seconds'];
      if (qr is! String || code is! String || expires is! num) {
        throw const FormatException('Pairing server returned incomplete challenge data.');
      }
      final parsedQr = Uri.tryParse(qr);
      final host = Uri.tryParse(parsedQr?.queryParameters['host'] ?? '');
      if (parsedQr == null || parsedQr.scheme != 'jarvis' || parsedQr.host != 'pair' ||
          host == null || host.scheme != 'https' || host.host.isEmpty) {
        throw Exception('Set JARVIS_PUBLIC_BASE_URL to your private HTTPS host URL in the PC .env file, then restart Jarvis.');
      }
      _timer?.cancel();
      setState(() {
        _qr = qr;
        _code = code;
        _secondsLeft = expires.toInt();
        _expiresAt = DateTime.now().add(Duration(seconds: _secondsLeft));
        _status = 'Scan this QR from Jarvis on your Android phone. Keep both devices on your private network.';
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final remaining = _expiresAt!.difference(DateTime.now()).inSeconds;
        setState(() => _secondsLeft = remaining.clamp(0, 180));
        if (_secondsLeft <= 0) {
          timer.cancel();
          setState(() { _qr = null; _status = 'QR expired. Generate a new one to pair.'; });
        }
      });
    } catch (error) {
      if (mounted) setState(() { _qr = null; _status = error.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pair an Android device')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.devices_rounded, size: 44, color: Color(0xff75e3ff)),
              const SizedBox(height: 14),
              const Text('One PC · One shared Jarvis backend', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xffa6b8ca))),
              const SizedBox(height: 22),
              if (_qr != null) Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(data: _qr!, version: QrVersions.auto, size: 260),
              ),
              if (_code.isNotEmpty && _qr != null) ...[
                const SizedBox(height: 14),
                SelectableText('Backup code: $_code', style: const TextStyle(fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.bold)),
                Text('Expires in $_secondsLeft seconds', style: const TextStyle(color: Color(0xffa6b8ca))),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _busy ? null : _generate,
                icon: const Icon(Icons.qr_code_2),
                label: Text(_qr == null ? 'Generate pairing QR' : 'Generate a new QR'),
              ),
              const SizedBox(height: 8),
              const Text('The QR contains a short-lived one-time challenge, never your AI API keys.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xff8295aa))),
            ],
          ),
        ),
      ),
    ),
  );
}
