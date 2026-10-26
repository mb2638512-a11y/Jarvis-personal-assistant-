import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_personal_assistant/main.dart';

void main() {
  testWidgets('Jarvis app renders its main interface', (tester) async {
    await tester.pumpWidget(const JarvisApp());
    expect(find.text('JARVIS'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
  });
}
