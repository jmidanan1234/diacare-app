import 'package:flutter_test/flutter_test.dart';
import 'package:diacare/models/patient.dart';

void main() {
  group('Patient selector label and search filtering tests', () {
    final patient1 = Patient(
      id: 'p-1',
      firstName: 'Jaime',
      lastName: 'Alcantara',
      middleName: 'M',
      birthDate: DateTime(1965, 5, 12),
      sex: 'Male',
      barangay: 'Bacolod',
      purok: 'Purok 4',
      diabetesType: 'Type 2',
      medications: 'Metformin 500mg',
      assignedBhwId: 'bhw-1',
      status: 'Approved',
      riskLevel: 'At Risk',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final patient2 = Patient(
      id: 'p-2',
      firstName: 'Maria',
      lastName: 'Santos',
      middleName: 'C',
      birthDate: DateTime(1978, 11, 23),
      sex: 'Female',
      barangay: 'Bacolod',
      purok: 'Purok Baybay',
      diabetesType: 'Type 1',
      medications: 'Insulin Glargine',
      assignedBhwId: 'bhw-1',
      status: 'Approved',
      riskLevel: 'Highly At Risk',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final patient3 = Patient(
      id: 'p-3',
      firstName: 'Juan',
      lastName: 'Dela Cruz',
      birthDate: DateTime(1955, 3, 10),
      sex: 'Male',
      barangay: 'Bacolod',
      purok: '3',
      diabetesType: 'Type 2',
      medications: null,
      assignedBhwId: 'bhw-1',
      status: 'Approved',
      riskLevel: 'Normal',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final patients = [patient1, patient2, patient3];

    test('Patient.fullName displays only full name without purok or address', () {
      expect(patient1.fullName, 'Jaime M. Alcantara');
      expect(patient2.fullName, 'Maria C. Santos');
      expect(patient3.fullName, 'Juan Dela Cruz');
      expect(patient1.fullName.contains('Purok'), isFalse);
      expect(patient2.fullName.contains('Baybay'), isFalse);
      expect(patient3.fullName.contains('Bacolod'), isFalse);
    });

    test('Live search filtering by name works accurately and case-insensitively', () {
      List<Patient> filter(String q) {
        final query = q.trim().toLowerCase();
        return query.isEmpty
            ? patients
            : patients.where((p) => p.fullName.toLowerCase().contains(query)).toList();
      }

      // Empty query returns all patients
      expect(filter('').length, 3);

      // Search by partial first name
      final jaimeResults = filter('jai');
      expect(jaimeResults.length, 1);
      expect(jaimeResults.first.fullName, 'Jaime M. Alcantara');

      // Search by last name case-insensitive
      final santosResults = filter('santos');
      expect(santosResults.length, 1);
      expect(santosResults.first.fullName, 'Maria C. Santos');

      // Search by middle initial
      final middleResults = filter('m.');
      expect(middleResults.length, 1);
      expect(middleResults.first.fullName, 'Jaime M. Alcantara');

      // Search with non-matching query produces empty list (triggers "No patient found")
      final noResults = filter('xyz non-existent');
      expect(noResults.isEmpty, isTrue);
    });
  });
}
