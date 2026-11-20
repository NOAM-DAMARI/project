import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/widgets/parasha_picker.dart';

void main() {
  testWidgets('switches between Torah books and the events category',
      (tester) async {
    ParashaSelection? selection;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ParashaPicker(
            value: 'בראשית',
            isEvent: false,
            onChanged: (value) => selection = value,
          ),
        ),
      ),
    ));

    await tester.tap(find.text('שמות'));
    await tester.pumpAndSettle();
    expect(find.text('יתרו'), findsOneWidget);
    expect(find.text('נח'), findsNothing);
    await tester.tap(find.text('יתרו'));
    expect(selection, (value: 'יתרו', isEvent: false));

    await tester.tap(find.text('אירועים / אישי'));
    await tester.pumpAndSettle();
    expect(find.text('פסח'), findsOneWidget);
    await tester.tap(find.text('פסח'));
    expect(selection, (value: 'פסח', isEvent: true));
  });
}
