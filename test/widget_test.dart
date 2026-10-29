import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_personal_assistant/main.dart';

void main() {
  testWidgets('Jarvis app renders its main interface on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const JarvisApp());
    await tester.pumpAndSettle();
    expect(find.text('JARVIS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
