import '../models/patient.dart';

/// Decides whether two registrations describe the same person.
///
/// The Add Patient form uses this to refuse a duplicate while the phone is
/// offline, and the sync uses it to fold an offline registration into the
/// record the RHU already has, so both apply exactly the same rule.
///
/// The old check compared the raw strings, so "juan", "Juan " and "JUAN"
/// were three different people, and a date of birth pulled from the server
/// (stored with a time of day) never equalled the same date picked on the
/// form (stored at midnight). Any of those let a second record through.
class PatientIdentity {
  final String firstName;
  final String lastName;
  final String? middleName;
  final DateTime birthDate;

  const PatientIdentity({
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.birthDate,
  });

  factory PatientIdentity.of(Patient patient) => PatientIdentity(
        firstName: patient.firstName,
        lastName: patient.lastName,
        middleName: patient.middleName,
        birthDate: patient.birthDate,
      );

  /// Case, surrounding spaces and runs of inner spaces never make two
  /// people different.
  static String normalizeName(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Only the calendar date counts. The time of day is an artefact of
  /// where the date was stored (form, dashboard, server timestamp).
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// A middle name only tells two people apart when both records have one
  /// and they disagree. Leaving the field blank must not be a way past the
  /// check, and "M." on one record matches "Mendoza" on the other.
  static bool middleNamesCompatible(String? a, String? b) {
    final x = normalizeName(a).replaceAll('.', '').trim();
    final y = normalizeName(b).replaceAll('.', '').trim();
    if (x.isEmpty || y.isEmpty) return true;
    if (x.length == 1 || y.length == 1) return x[0] == y[0];
    return x == y;
  }

  bool matches(PatientIdentity other) =>
      normalizeName(firstName) == normalizeName(other.firstName) &&
      normalizeName(lastName) == normalizeName(other.lastName) &&
      sameDay(birthDate, other.birthDate) &&
      middleNamesCompatible(middleName, other.middleName);
}
