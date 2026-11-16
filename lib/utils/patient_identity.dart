import '../models/patient.dart';

/// Decides whether two registrations describe the same person.
///
/// A patient may be registered only once. Two records with the same first
/// name and surname are the same person, even when the purok, barangay,
/// middle name or date of birth differ, so only those two names are
/// compared.
///
/// The Add Patient form uses this to refuse a duplicate while the phone is
/// offline, and the sync uses it to fold an offline registration into the
/// record the RHU already has, so both apply exactly the same rule. The
/// dashboard and /api/bhw-patient-check normalise names the same way.
class PatientIdentity {
  final String firstName;
  final String lastName;

  const PatientIdentity({
    required this.firstName,
    required this.lastName,
  });

  factory PatientIdentity.of(Patient patient) => PatientIdentity(
        firstName: patient.firstName,
        lastName: patient.lastName,
      );

  /// Case, surrounding spaces and runs of inner spaces never make two
  /// people different: "juan", "Juan " and "JUAN" are one name.
  static String normalizeName(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool matches(PatientIdentity other) =>
      normalizeName(firstName) == normalizeName(other.firstName) &&
      normalizeName(lastName) == normalizeName(other.lastName);
}
