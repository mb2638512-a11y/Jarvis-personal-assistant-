import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_personal_assistant/llm_client.dart';

void main() {
  group('LlmClient task classification', () {
    test('routes software engineering prompts to coding', () {
      expect(LlmClient.classifyTask('Please debug this Flutter API function'), 'coding');
    });

    test('routes deep analysis prompts to reasoning', () {
      expect(LlmClient.classifyTask('Analyze deeply this architecture and compare in depth'), 'reasoning');
    });

    test('routes cost-aware prompts to low cost', () {
      expect(LlmClient.classifyTask('Use a cheap model with low cost'), 'low_cost');
    });

    test('routes short-response prompts to fast', () {
      expect(LlmClient.classifyTask('Give a quick summary'), 'fast');
    });

    test('defaults ordinary prompts to general', () {
      expect(LlmClient.classifyTask('What is the capital of Pakistan?'), 'general');
    });
  });
}
