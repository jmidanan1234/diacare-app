import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diacare/services/risk_classifier.dart';
import 'package:diacare/widgets/shared_widgets.dart';

void main() {
  group('RiskClassifier.getTrend - excursion-based glucose trend tests', () {
    test('Fewer than 3 readings returns Stable', () {
      expect(RiskClassifier.getTrend([]), 'Stable');
      expect(RiskClassifier.getTrend([120.0]), 'Stable');
      expect(RiskClassifier.getTrend([200.0, 190.0]), 'Stable');
    });

    test('Readings inside 70-180 mg/dL target range always return Stable', () {
      // Newest first: 160, 130, 90 (all within 70-180)
      expect(RiskClassifier.getTrend([160.0, 130.0, 90.0]), 'Stable');
      // Decreasing inside range
      expect(RiskClassifier.getTrend([80.0, 110.0, 170.0]), 'Stable');
      // Fluctuating inside range
      expect(RiskClassifier.getTrend([75.0, 175.0, 100.0]), 'Stable');
    });

    test('Distance outside target grew by >= 15 mg/dL returns Worsening', () {
      // Hyperglycemia worsening: oldest = 185 (excursion +5), newest = 210 (excursion +30). Change = +25 >= 15
      expect(RiskClassifier.getTrend([210.0, 195.0, 185.0]), 'Worsening');

      // Hypoglycemia worsening: oldest = 65 (excursion -5, abs 5), newest = 45 (excursion -25, abs 25). Change = 20 >= 15
      expect(RiskClassifier.getTrend([45.0, 55.0, 65.0]), 'Worsening');
    });

    test('Distance outside target shrank by >= 15 mg/dL returns Improving', () {
      // Hyperglycemia improving: oldest = 220 (excursion +40), newest = 190 (excursion +10). Change = -30 <= -15
      expect(RiskClassifier.getTrend([190.0, 205.0, 220.0]), 'Improving');

      // Hyperglycemia returning to normal: oldest = 210 (excursion +30), newest = 150 (excursion 0). Change = -30 <= -15
      expect(RiskClassifier.getTrend([150.0, 180.0, 210.0]), 'Improving');

      // Hypoglycemia improving: oldest = 45 (abs 25), newest = 65 (abs 5). Change = -20 <= -15
      expect(RiskClassifier.getTrend([65.0, 55.0, 45.0]), 'Improving');
    });

    test('Swung across range (low <-> high) by >= 15 mg/dL returns Worsening', () {
      // Oldest = 60 (excursion -10), Newest = 190 (excursion +10). newest * oldest < 0, abs(10) + abs(-10) = 20 >= 15
      expect(RiskClassifier.getTrend([190.0, 120.0, 60.0]), 'Worsening');
    });

    test('Changes within dead-band (< 15 mg/dL) return Stable', () {
      // Oldest = 190 (excursion +10), Newest = 200 (excursion +20). Change = +10 < 15
      expect(RiskClassifier.getTrend([200.0, 195.0, 190.0]), 'Stable');
    });

    test('countValidGlucose ignores null and zero values', () {
      expect(RiskClassifier.countValidGlucose([]), 0);
      expect(RiskClassifier.countValidGlucose([null, 0.0]), 0);
      expect(RiskClassifier.countValidGlucose([120.0, null, 0.0]), 1);
      expect(RiskClassifier.countValidGlucose([120.0, 110.0]), 2);
      expect(RiskClassifier.countValidGlucose([120.0, 110.0, 130.0]), 3);
    });

    test('hasEnoughTrendData requires at least 3 valid readings', () {
      expect(RiskClassifier.hasEnoughTrendData([]), false);
      expect(RiskClassifier.hasEnoughTrendData([120.0]), false);
      expect(RiskClassifier.hasEnoughTrendData([120.0, 110.0]), false);
      expect(RiskClassifier.hasEnoughTrendData([120.0, 110.0, 130.0]), true);
      expect(RiskClassifier.hasEnoughTrendData([120.0, null, 110.0, 130.0]), true);
    });
  });

  group('TrendChip display tests for valid reading count', () {
    testWidgets('0 or 1 reading does NOT display trend badge or text', (tester) async {
      // 0 readings
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TrendChip(
            trend: 'Stable',
            glucoseReadings: [],
            compact: false,
          ),
        ),
      ));
      expect(find.text('Stable'), findsNothing);
      expect(find.text('Not enough data (needs 3 readings)'), findsNothing);

      // 1 reading
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TrendChip(
            trend: 'Stable',
            glucoseReadings: [120.0],
            compact: false,
          ),
        ),
      ));
      expect(find.text('Stable'), findsNothing);
      expect(find.text('Not enough data (needs 3 readings)'), findsNothing);
    });

    testWidgets('Exactly 2 readings displays text in non-compact spot, hides in compact spot', (tester) async {
      // Compact spot (profile header): hidden, no badge, no text
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TrendChip(
            trend: 'Stable',
            glucoseReadings: [120.0, 110.0],
            compact: true,
          ),
        ),
      ));
      expect(find.text('Stable'), findsNothing);
      expect(find.text('Not enough data (needs 3 readings)'), findsNothing);

      // Non-compact spot (Trends tab "Overall Trend:" row): displays helper text, no badge
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TrendChip(
            trend: 'Stable',
            glucoseReadings: [120.0, 110.0],
            compact: false,
          ),
        ),
      ));
      expect(find.text('Stable'), findsNothing);
      expect(find.text('Not enough data (needs 3 readings)'), findsOneWidget);
    });

    testWidgets('3 or more readings displays the trend badge normally', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TrendChip(
            trend: 'Stable',
            glucoseReadings: [120.0, 110.0, 115.0],
            compact: false,
          ),
        ),
      ));
      expect(find.text('Stable'), findsOneWidget);
      expect(find.text('Not enough data (needs 3 readings)'), findsNothing);
    });

    testWidgets('TrendChip with 2 readings in a narrow row does not overflow', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Row(
              children: const [
                Text('Overall Trend:'),
                SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TrendChip(
                      trend: 'Stable',
                      glucoseReadings: [120.0, 110.0],
                      compact: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Not enough data (needs 3 readings)'), findsOneWidget);
    });
  });
}

