import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_assistant/main.dart';

void main() {
  testWidgets('Jarvis dashboard renders', (tester) async {
    await tester.pumpWidget(const JarvisApp());
    expect(find.text('JARVIS'), findsWidgets);
    expect(find.text('YOUR INTELLIGENCE, AMPLIFIED.'), findsOneWidget);
  });
}
