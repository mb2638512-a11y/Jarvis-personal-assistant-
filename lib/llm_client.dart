import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Local-first OpenAI-compatible client with task-aware provider ordering and fallback.
class LlmClient {
  static const _storage = FlutterSecureStorage();
  static const _configKey = 'jarvis.llm.providers.v1';

  static String classifyTask(String message) {
    final text = message.toLowerCase();
    if (RegExp(r'\b(code|coding|program|debug|compile|flutter|python|javascript|typescript|rust|golang|sql|github|api|function|class|bug|refactor)\b').hasMatch(text)) return 'coding';
    if (RegExp(r'\b(prove|derive|analyze deeply|reason|architecture|compare in depth|complex|mathematical|algorithm|research)\b').hasMatch(text)) return 'reasoning';
    if (RegExp(r'\b(cheap|low cost|budget|token cost|economical)\b').hasMatch(text)) return 'low_cost';
    if (RegExp(r'\b(quick|brief|fast|short answer|translate|summarize)\b').hasMatch(text)) return 'fast';
    return 'general';
  }

  static Future<String?> send(String message) async {
    final raw = await _storage.read(key: _configKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final providers = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (providers.isEmpty) return null;
    final task = classifyTask(message);
    providers.sort((a, b) {
      int rank(Map<String, dynamic> p) {
        if ((p['model'] as String? ?? '').trim().isEmpty) return 10;
        if ((p['routingMode'] as String? ?? 'automatic') == 'manual') return p['task'] == task ? 0 : 2;
        if (p['task'] == task) return 0;
        if (p['task'] == 'general') return 1;
        return 3;
      }
      return rank(a).compareTo(rank(b));
    });

    Object? lastError;
    for (final provider in providers) {
      final id = provider['id'] as String?;
      final model = (provider['model'] as String? ?? '').trim();
      final base = (provider['baseUrl'] as String? ?? '').trim().replaceFirst(RegExp(r'/+$'), '');
      if (id == null || model.isEmpty) continue;
      final key = await _storage.read(key: 'jarvis.llm.key.$id') ?? '';
      final uri = Uri.tryParse(base + '/chat/completions');
      if (uri == null || !uri.hasScheme || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
          !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
          (uri.scheme.toLowerCase() != 'https' && !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host))) {
        lastError = Exception('Provider URL is invalid or not secure.');
        continue;
      }
      try {
        final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
        if (key.isNotEmpty) headers['Authorization'] = 'Bearer ' + key;
        final custom = (provider['headers'] as String? ?? '').trim();
        if (custom.isNotEmpty) {
          final extra = jsonDecode(custom);
          if (extra is! Map) throw const FormatException('Custom headers must be a JSON object.');
          for (final entry in extra.entries) {
            final name = entry.key.toString();
            if (name.toLowerCase() == 'authorization' || name.toLowerCase() == 'host') {
              throw const FormatException('Authorization and Host cannot be custom headers.');
            }
            headers[name] = entry.value.toString();
          }
        }
        final response = await http.post(uri, headers: headers, body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': 'You are Jarvis, a helpful personal assistant. Be accurate and honest.'},
            {'role': 'user', 'content': message},
          ],
        })).timeout(const Duration(seconds: 60));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = Exception('Provider returned HTTP ' + response.statusCode.toString() + '.');
          continue;
        }
        final body = jsonDecode(response.body);
        final choices = body is Map ? body['choices'] : null;
        final first = choices is List && choices.isNotEmpty ? choices.first : null;
        final msg = first is Map ? first['message'] : null;
        final reply = msg is Map ? msg['content'] : null;
        if (reply is String && reply.trim().isNotEmpty) return reply.trim();
        lastError = Exception('Provider returned no text response.');
      } catch (error) { lastError = error; }
    }
    if (lastError != null) throw Exception('All configured LLM providers failed. Last error: ' + lastError.toString());
    return null;
  }
}
