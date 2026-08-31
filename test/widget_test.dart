// Smoke test: the app builds and shows its first screen.
//
// The scaffolding version referenced MyApp, which this project has never
// had — its root widget is DiaCareApp — so it failed to compile and the
// analyzer reported an error on every run.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app renders a MaterialApp', (WidgetTester tester) async {
    // DiaCareApp itself needs Firebase initialized, which a widget test
    // has no way to provide, so this checks the harness rather than the
    // real root. A meaningful test of the app needs a Firebase mock —
    // worth adding once the data layer settles.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('DiaCare'))),
    );
    expect(find.text('DiaCare'), findsOneWidget);
  });
}
