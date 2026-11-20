import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/main.dart';

void main() {
  testWidgets('App starts and shows the startup screen', (tester) async {
    await tester.pumpWidget(const StartupGate());
    await tester.pump();
    expect(find.byType(StartupGate), findsOneWidget);
  });
}
