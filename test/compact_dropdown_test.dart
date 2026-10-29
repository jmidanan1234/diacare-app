import 'package:diacare/utils/constants.dart';
import 'package:diacare/widgets/compact_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('patient dropdown selects a value and retains it after rebuild',
      (tester) async {
    String? selected = 'Male';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Padding(
        padding: const EdgeInsets.all(16),
        child: StatefulBuilder(
            builder: (context, setState) => CompactDropdownField(
                  label: 'Sex *',
                  value: selected,
                  options: AppConstants.sexOptions,
                  onChanged: (value) => setState(() => selected = value),
                )),
      )),
    ));
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    final option = find.widgetWithText(MenuItemButton, 'Female').last;
    expect(tester.getSize(option).width, lessThanOrEqualTo(280));
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(selected, 'Female');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Female');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'barangay menu scrolls in a bounded popup and keeps required validation',
      (tester) async {
    final form = GlobalKey<FormState>();
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
            key: form,
            child: StatefulBuilder(
                builder: (context, setState) => CompactDropdownField(
                      label: 'Barangay *',
                      value: selected,
                      options: AppConstants.barangays,
                      validator: (value) => value == null ? 'Required' : null,
                      onChanged: (value) => setState(() => selected = value),
                    ))),
      )),
    ));
    expect(form.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SingleChildScrollView).last).height,
        lessThanOrEqualTo(240));
    final last =
        find.widgetWithText(MenuItemButton, AppConstants.barangays.last).last;
    await tester.scrollUntilVisible(last, 120,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(selected, AppConstants.barangays.last);
    expect(form.currentState!.validate(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
