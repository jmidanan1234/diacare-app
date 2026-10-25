import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/patient.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';

class AddPatientScreen extends StatefulWidget {
  /// When provided, the screen edits this patient instead of adding a new one.
  final Patient? existingPatient;

  const AddPatientScreen({
    super.key,
    this.existingPatient,
  });

  bool get isEditing => existingPatient != null;

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();

  // Keys used to scroll to the first missing required field.
  final _firstNameKey = GlobalKey();
  final _lastNameKey = GlobalKey();
  final _birthKey = GlobalKey();
  final _barangayKey = GlobalKey();
  final _purokKey = GlobalKey();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _physicianController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _emergencyNumberController = TextEditingController();

  DateTime? _birthDate;
  DateTime? _diagnosisDate;

  /// Date of birth is not a real FormField, so it needs its own error flag.
  bool _birthDateError = false;

  String _sex = AppConstants.sexOptions[0];
  String _diabetesType = AppConstants.diabetesTypes[1];

  /// Defaults to the worker's own barangay in initState — that is where
  /// nearly every household visit is — but stays editable for the
  /// patient who lives across the boundary.
  String? _barangay;
  final _purokController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final own = context.read<AppProvider>().currentUser?.barangay.trim() ?? '';
    _barangay = AppConstants.barangays.contains(own) ? own : null;

    if (widget.isEditing) {
      _prefillFromPatient(widget.existingPatient!);
    }
  }

  void _prefillFromPatient(Patient p) {
    _firstNameController.text = p.firstName;
    _middleNameController.text = p.middleName ?? '';
    _lastNameController.text = p.lastName;
    _birthDate = p.birthDate;
    _sex = p.sex;
    _barangay = AppConstants.barangays.contains(p.barangay) ? p.barangay : null;
    _purokController.text = p.purok;
    _contactController.text = p.contactNumber ?? '';
    _diabetesType = AppConstants.diabetesTypes.contains(p.diabetesType)
        ? p.diabetesType
        : AppConstants.diabetesTypes[3];
    _diagnosisDate = p.diagnosisDate;
    _medicationsController.text = p.medications ?? '';
    _physicianController.text = p.attendingPhysician ?? '';
    _emergencyContactController.text = p.emergencyContact ?? '';
    _emergencyNumberController.text = p.emergencyContactNumber ?? '';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _purokController.dispose();
    _contactController.dispose();
    _medicationsController.dispose();
    _physicianController.dispose();
    _emergencyContactController.dispose();
    _emergencyNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({bool isBirth = true}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isBirth
          ? (_birthDate ?? DateTime(1970))
          : (_diagnosisDate ?? DateTime.now()),
      // Diagnosis can't predate the patient's own birth — without this,
      // the picker would happily accept a diagnosis year before they were born.
      firstDate: isBirth ? DateTime(1920) : (_birthDate ?? DateTime(1950)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isBirth) {
          _birthDate = picked;
          _birthDateError = false;
          // If a diagnosis date was already set and is now before the
          // (updated) birth date, it's no longer valid — clear it rather
          // than silently keeping an impossible date.
          if (_diagnosisDate != null && _diagnosisDate!.isBefore(picked)) {
            _diagnosisDate = null;
          }
        } else {
          _diagnosisDate = picked;
        }
      });
    }
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.15, // leaves a little space above the field
    );
  }

  /// Scrolls to the first required field that is still empty, in the same
  /// order they appear on the form. Optional fields are never touched.
  void _scrollToFirstMissing() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_firstNameController.text.trim().isEmpty) {
        _scrollTo(_firstNameKey);
      } else if (_lastNameController.text.trim().isEmpty) {
        _scrollTo(_lastNameKey);
      } else if (_birthDate == null) {
        _scrollTo(_birthKey);
      } else if (_barangay == null) {
        _scrollTo(_barangayKey);
      } else if (_purokController.text.trim().isEmpty) {
        _scrollTo(_purokKey);
      }
    });
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final birthMissing = _birthDate == null;

    if (birthMissing) setState(() => _birthDateError = true);

    if (!formValid || birthMissing) {
      _scrollToFirstMissing();
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<AppProvider>();

    if (widget.isEditing) {
      // Update existing patient
      final updatedPatient = widget.existingPatient!.copyWith(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        middleName: _middleNameController.text.trim().isEmpty ? null : _middleNameController.text.trim(),
        birthDate: _birthDate!,
        sex: _sex,
        barangay: _barangay!,
        purok: _purokController.text.trim(),
        contactNumber: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
        diabetesType: _diabetesType,
        diagnosisDate: _diagnosisDate,
        medications: _medicationsController.text.trim().isEmpty ? null : _medicationsController.text.trim(),
        attendingPhysician: _physicianController.text.trim().isEmpty ? null : _physicianController.text.trim(),
        emergencyContact: _emergencyContactController.text.trim().isEmpty ? null : _emergencyContactController.text.trim(),
        emergencyContactNumber: _emergencyNumberController.text.trim().isEmpty ? null : _emergencyNumberController.text.trim(),
        updatedAt: DateTime.now(),
      );

      await provider.updatePatient(updatedPatient);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient updated successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, updatedPatient);
      }
      return;
    }

    // Add new patient logic
    final id = provider.newPatientId();

    // Duplicate check
    final isDuplicate = await provider.checkDuplicate(
      _firstNameController.text.trim(),
      _lastNameController.text.trim(),
      _birthDate!,
      id,
    );

    if (isDuplicate && mounted) {
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Duplicate Patient'),
          content: const Text(
            'A patient with the same name and date of birth already exists in the system.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    /* The check above only sees this phone. Someone covering the next
       purok may already have this patient, and neither worker would ever
       find out — the RHU ends up with one person in two rows and half
       their readings under each. Online only, and a warning rather than
       a block: the same person really can be registered twice for good
       reasons, and a barangay with no signal must still be able to
       register anyone. */
    final registeredBy = await provider.checkRemoteDuplicate(
      _firstNameController.text.trim(),
      _lastNameController.text.trim(),
      _birthDate!,
    );

    if (registeredBy != null && mounted) {
      setState(() => _isLoading = false);
      final who = registeredBy.isEmpty
          ? 'is already on the RHU register'
          : 'is already registered by $registeredBy';
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Already Registered?'),
          content: Text(
            'A patient with this name and date of birth $who.\n\n'
            'Registering them again creates a second record, splitting '
            'their readings across both. Continue only if this is a '
            'different person.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Register Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
      setState(() => _isLoading = true);
    }

    final now = DateTime.now();
    final patient = Patient(
      id: id,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      middleName: _middleNameController.text.trim().isEmpty ? null : _middleNameController.text.trim(),
      birthDate: _birthDate!,
      sex: _sex,
      barangay: _barangay!,
      purok: _purokController.text.trim(),
      contactNumber: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
      diabetesType: _diabetesType,
      diagnosisDate: _diagnosisDate,
      medications: _medicationsController.text.trim().isEmpty ? null : _medicationsController.text.trim(),
      attendingPhysician: _physicianController.text.trim().isEmpty ? null : _physicianController.text.trim(),
      emergencyContact: _emergencyContactController.text.trim().isEmpty ? null : _emergencyContactController.text.trim(),
      emergencyContactNumber: _emergencyNumberController.text.trim().isEmpty ? null : _emergencyNumberController.text.trim(),
      assignedBhwId: provider.currentUser!.id,
      // No approval queue any more — a patient a BHW registers on a
      // household visit is active from the moment they are saved, and
      // syncs to the RHU dashboard as such.
      status: AppConstants.statusApproved,
      riskLevel: '',
      createdAt: now,
      updatedAt: now,
    );

    await provider.addPatient(patient);
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient saved. They will sync to the RHU dashboard on your next sync.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      );

  /// Wraps a field with bottom spacing. Pass [key] on required fields so
  /// [_scrollToFirstMissing] can scroll to them.
  Widget _field(Widget child, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 14),
        child: child,
      );

  /// Validates Philippine mobile numbers. Optional field — only validates
  /// format if something was entered, since not every patient/contact has
  /// a phone. Accepts 09XXXXXXXXX or +639XXXXXXXXX (11 or 13 digits incl. +63).
  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional field
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    final isLocal = digitsOnly.length == 11 && digitsOnly.startsWith('09');
    final isIntl = digitsOnly.length == 12 && digitsOnly.startsWith('639');
    if (!isLocal && !isIntl) {
      return 'Enter a valid PH mobile number (e.g. 09171234567)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit Patient' : 'Add New Patient')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('Personal Information'),

              // First name (required)
              _field(
                TextFormField(
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'First Name *'),
                  validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                ),
                key: _firstNameKey,
              ),

              _field(TextFormField(
                controller: _middleNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Middle Name'),
              )),

              // Last name (required)
              _field(
                TextFormField(
                  controller: _lastNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Last Name *'),
                  validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                ),
                key: _lastNameKey,
              ),

              // Birth date (required) with inline error
              _field(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _pickDate(isBirth: true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _birthDateError ? Colors.red : AppColors.divider,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 18, color: AppColors.textSecondary),
                            const SizedBox(width: 10),
                            Text(
                              _birthDate != null
                                  ? 'DOB: ${DateFormat('MMMM d, y').format(_birthDate!)}'
                                  : 'Date of Birth *',
                              style: TextStyle(
                                fontSize: 14,
                                color: _birthDate != null
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_birthDateError)
                      const Padding(
                        padding: EdgeInsets.only(left: 16, top: 6),
                        child: Text(
                          'Required',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                key: _birthKey,
              ),

              // Sex
              _field(DropdownButtonFormField<String>(
                initialValue: _sex,
                decoration: const InputDecoration(labelText: 'Sex *'),
                items: AppConstants.sexOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _sex = v!),
              )),

              // Barangay + Purok replace the old free-text Home Address:
              // specific enough to find the house, consistent enough to
              // filter and report on.
              _field(
                DropdownButtonFormField<String>(
                  initialValue: _barangay,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Barangay *'),
                  items: AppConstants.barangays
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setState(() => _barangay = v),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                key: _barangayKey,
              ),

              // Purok — free text so a BHW can enter exactly what's on
              // record for this patient, rather than being limited to a
              // fixed list of preset options.
              _field(
                TextFormField(
                  controller: _purokController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Purok *', hintText: 'e.g. Purok 3'),
                  validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                ),
                key: _purokKey,
              ),

              _field(TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Contact Number', hintText: 'e.g. 09171234567'),
                validator: _validatePhone,
              )),

              _sectionHeader('Medical Information'),
              _field(DropdownButtonFormField<String>(
                initialValue: _diabetesType,
                decoration: const InputDecoration(labelText: 'Diabetes Type *'),
                items: AppConstants.diabetesTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _diabetesType = v!),
              )),

              // Diagnosis date
              _field(GestureDetector(
                onTap: () => _pickDate(isBirth: false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text(
                        _diagnosisDate != null
                            ? 'Diagnosis: ${DateFormat('MMMM d, y').format(_diagnosisDate!)}'
                            : 'Date of Diagnosis (optional)',
                        style: TextStyle(
                          fontSize: 14,
                          color: _diagnosisDate != null ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )),

              _field(TextFormField(
                controller: _medicationsController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Current Medications'),
                maxLines: 2,
              )),

              _field(TextFormField(
                controller: _physicianController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Attending Physician'),
              )),

              _sectionHeader('Emergency Contact'),
              _field(TextFormField(
                controller: _emergencyContactController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Emergency Contact Name'),
              )),
              _field(TextFormField(
                controller: _emergencyNumberController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Emergency Contact Number', hintText: 'e.g. 09171234567'),
                validator: _validatePhone,
              )),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(widget.isEditing ? 'Update' : 'Save'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}