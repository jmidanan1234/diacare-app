import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diacare/services/risk_classifier.dart';
import 'package:diacare/utils/constants.dart';

void main() {
  group('Offline Authentication & Password Hashing Tests', () {
    String hashPassword(String password, String salt) {
      final bytes = utf8.encode(password + salt);
      return sha256.convert(bytes).toString();
    }

    test('Pre-seeded Maria Santos credentials match offline hash', () {
      const password = 'bhw1234';
      const salt = 'a1b2c3d4e5f6';
      const expectedHash =
          '842874c1bd7147eab84b6ebbe57fb79a86c88731d3a91c8ae82ac86d516aa63f';

      final hash = hashPassword(password, salt);
      expect(hash, equals(expectedHash));
    });

    test('Pre-seeded Carlos Reyes credentials match offline hash', () {
      const password = 'temp1234';
      const salt = 'f1e2d3c4b5a6';
      const expectedHash =
          '74fb666e7245b0994d87740b1114b3681202c93027ec6ce8053204570998f785';

      final hash = hashPassword(password, salt);
      expect(hash, equals(expectedHash));
    });
  });

  group('Offline Risk Classification Tests (ADA 2026 Standards)', () {
    test('Highly At Risk when glucose > 250 mg/dL (Level 2 hyperglycemia)', () {
      final risk = RiskClassifier.classify(
        bloodGlucose: 260,
        systolicBP: 120,
        diastolicBP: 80,
      );
      expect(risk, equals(AppConstants.riskHigh));
    });

    test('Highly At Risk when glucose < 54 mg/dL (Level 2 hypoglycemia)', () {
      final risk = RiskClassifier.classify(
        bloodGlucose: 50,
        systolicBP: 120,
        diastolicBP: 80,
      );
      expect(risk, equals(AppConstants.riskHigh));
    });

    test('At Risk when glucose is 54-69 mg/dL (Level 1 hypoglycemia)', () {
      final risk = RiskClassifier.classify(
        bloodGlucose: 65,
        systolicBP: 120,
        diastolicBP: 80,
      );
      expect(risk, equals(AppConstants.riskModerate));
    });

    test('At Risk when glucose is 181-250 mg/dL (Level 1 hyperglycemia)', () {
      final risk = RiskClassifier.classify(
        bloodGlucose: 200,
        systolicBP: 120,
        diastolicBP: 80,
      );
      expect(risk, equals(AppConstants.riskModerate));
    });

    test('Normal when glucose is within target range 70-180 mg/dL', () {
      final risk = RiskClassifier.classify(
        bloodGlucose: 150,
        systolicBP: 120,
        diastolicBP: 80,
      );
      expect(risk, equals(AppConstants.riskNormal));
    });

    test('Normal Risk when all vitals are optimal', () {
      final risk = RiskClassifier.classify(
        bloodGlucose: 95,
        systolicBP: 115,
        diastolicBP: 75,
      );
      expect(risk, equals(AppConstants.riskNormal));
    });
  });
}
