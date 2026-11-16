import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../utils/patient_identity.dart';
import 'auth_service.dart';

/// A patient already on the RHU register under the same first name and
/// surname as one being registered.
class RegisterMatch {
  final String patientId;

  /// The existing record is assigned to the worker who asked.
  final bool assignedToYou;

  /// The existing record is assigned to some health worker.
  final bool assigned;

  /// The name of the other worker who holds it; empty when it is the
  /// caller's own, unassigned, or the name is unknown.
  final String heldBy;
  final String barangay;
  final String purok;
  final bool inactive;

  const RegisterMatch({
    required this.patientId,
    this.assignedToYou = false,
    this.assigned = false,
    this.heldBy = '',
    this.barangay = '',
    this.purok = '',
    this.inactive = false,
  });

  factory RegisterMatch.fromJson(Map<String, dynamic> json) => RegisterMatch(
        patientId: json['patientId'] as String? ?? '',
        assignedToYou: json['assignedToYou'] == true,
        assigned: json['assigned'] == true,
        heldBy: json['heldBy'] as String? ?? '',
        barangay: json['barangay'] as String? ?? '',
        purok: json['purok'] as String? ?? '',
        inactive: json['inactive'] == true,
      );

  String get _place => [
        if (purok.trim().isNotEmpty) purok.trim(),
        if (barangay.trim().isNotEmpty) barangay.trim(),
      ].join(', ');

  /// Where the existing record is, as the end of a sentence that starts
  /// with the patient's name.
  String describe() {
    final place = _place.isEmpty ? '' : ' ($_place)';
    if (inactive) {
      return 'is already on the RHU register$place, but was marked '
          'inactive. Ask the RHU to reactivate them instead.';
    }
    if (assignedToYou) {
      return 'is already on your patient list$place. Sync to receive the '
          'latest copy of their record.';
    }
    if (assigned) {
      return heldBy.isEmpty
          ? 'is already registered$place and assigned to another health '
              'worker.'
          : 'is already registered$place and assigned to $heldBy.';
    }
    return 'is already registered at the RHU$place.';
  }
}

/// One patient to look up: its own id, if it has one, so it is never
/// reported as a duplicate of itself.
typedef RegisterQuery = ({String? id, PatientIdentity identity});

/// Looks the given patients up on the whole RHU register. Returns one
/// entry per query, in order: the matching record, or null. Throws when
/// the register could not be reached, so a caller can tell "no
/// duplicate" apart from "could not check".
typedef RegisterLookup = Future<List<RegisterMatch?>> Function(
    List<RegisterQuery> queries);

/// Asks /api/bhw-patient-check whether a patient is already registered.
///
/// The security rules only let a phone read the patients assigned to its
/// own worker, so a patient the RHU encoded on the dashboard, or one held
/// by another worker, can only be found through the server.
class RegisterCheckService {
  static Future<List<RegisterMatch?>> lookup(
      List<RegisterQuery> queries) async {
    if (queries.isEmpty) return const [];
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) {
      throw StateError('Sign in again to check the RHU register.');
    }

    final results = <RegisterMatch?>[];
    // The endpoint takes at most 200 patients a request.
    for (var offset = 0; offset < queries.length; offset += 200) {
      final batch = queries.skip(offset).take(200).toList();
      final res = await http
          .post(
            Uri.parse('${AuthService.apiBase}/api/bhw-patient-check'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'patients': [
                for (final q in batch)
                  {
                    'id': q.id ?? '',
                    'firstName': q.identity.firstName,
                    'lastName': q.identity.lastName,
                  }
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        String? error;
        try {
          error = (jsonDecode(res.body) as Map<String, dynamic>?)?['error']
              ?.toString();
        } catch (_) {}
        throw StateError(
            error ?? 'The RHU register could not be checked (${res.statusCode}).');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = body['matches'] as List<dynamic>? ?? const [];
      if (matches.length != batch.length) {
        throw StateError('The RHU register gave an incomplete answer.');
      }
      for (final match in matches) {
        results.add(match is Map<String, dynamic>
            ? RegisterMatch.fromJson(match)
            : null);
      }
    }
    return results;
  }
}
