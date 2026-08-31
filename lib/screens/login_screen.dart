import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import '../utils/theme.dart';
import '../utils/constants.dart';
import 'main_screen.dart';
import 'force_change_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Captured once (this screen is portrait-locked, so it never legitimately
  // changes) and reused for every proportional size in this screen. Reading
  // MediaQuery live instead would make every font/icon/padding shrink in
  // lockstep with the keyboard-shrunk viewport, which reads as the whole
  // screen "zooming" the moment a field gets focus.
  Size? _frozenSize;
  EdgeInsets? _frozenViewPadding;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frozenSize ??= MediaQuery.of(context).size;
    _frozenViewPadding ??= MediaQuery.of(context).padding;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = AuthService();
    final success = await auth.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      final mustChange = auth.currentUser?.mustChangePassword ?? false;
      if (mustChange) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const ForceChangePasswordScreen()),
          );
        }
        return;
      }
      await context.read<AppProvider>().loadAll();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Invalid username or password.';
      });
    }
  }

  /// BHW accounts are provisioned by the BHN, so password resets are
  /// BHN-mediated rather than self-service email reset — most BHWs won't
  /// reliably have a registered email in a barangay setting, and this keeps
  /// the access-control model consistent with how accounts are created.
  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_reset_rounded,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'Forgot Password?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'Only your Barangay Health Nurse (BHN) can reset your password. '
              'Please ask your BHN to reset it for you.\n\n'
              'After that, you will make a new password the next time you sign in.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: AppColors.textSecondary),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got It'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Force portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    final size = _frozenSize!;
    final padding = _frozenViewPadding!;
    // Available height minus status bar and nav bar
    final availableHeight = size.height - padding.top - padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.primary,
      // Let the body shrink for the keyboard; the LayoutBuilder below turns
      // that shrink into scroll room instead of squeezing the layout.
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.hero),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    // ── Top branding section ── fixed proportion of the frozen
                    // screen height, so it never resizes when the keyboard opens.
                    SizedBox(
                      height: availableHeight * 0.35,
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.08,
                          vertical: availableHeight * 0.02,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: availableHeight * 0.09,
                              height: availableHeight * 0.09,
                              padding: EdgeInsets.all(availableHeight * 0.012),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/logo_login.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(height: availableHeight * 0.015),
                            Text(
                              AppConstants.appName,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: availableHeight * 0.042,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: availableHeight * 0.006),
                            Text(
                              AppConstants.appTagline,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: availableHeight * 0.017,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Login card section ── fixed proportion of the frozen
                    // screen height; scrolls into view via the SingleChildScrollView
                    // above instead of shrinking when the keyboard opens.
                    SizedBox(
                      height: availableHeight * 0.65,
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(32)),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 24,
                              offset: Offset(0, -6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            size.width * 0.07,
                            availableHeight * 0.03,
                            size.width * 0.07,
                            availableHeight * 0.02,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(
                                          availableHeight * 0.012),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.lock_person_rounded,
                                        color: AppColors.primary,
                                        size: availableHeight * 0.026,
                                      ),
                                    ),
                                    SizedBox(width: size.width * 0.03),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'BHW Sign In',
                                          style: TextStyle(
                                            fontSize: availableHeight * 0.026,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Authorized personnel only',
                                          style: TextStyle(
                                            fontSize: availableHeight * 0.016,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                SizedBox(height: availableHeight * 0.025),

                                // Error banner
                                if (_errorMessage != null) ...[
                                  Container(
                                    padding:
                                        EdgeInsets.all(availableHeight * 0.014),
                                    decoration: BoxDecoration(
                                      color: AppColors.error
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.error
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline,
                                            color: AppColors.error,
                                            size: availableHeight * 0.022),
                                        SizedBox(width: size.width * 0.02),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: TextStyle(
                                              color: AppColors.error,
                                              fontSize: availableHeight * 0.017,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: availableHeight * 0.018),
                                ],

                                // Username
                                Text(
                                  'Username',
                                  style: TextStyle(
                                    fontSize: availableHeight * 0.018,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: availableHeight * 0.008),
                                TextFormField(
                                  controller: _usernameController,
                                  keyboardType: TextInputType.text,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  style: TextStyle(
                                      fontSize: availableHeight * 0.02),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. bhw.santos',
                                    hintStyle: TextStyle(
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.6),
                                      fontSize: availableHeight * 0.019,
                                    ),
                                    prefixIcon: Icon(Icons.person_outline,
                                        size: availableHeight * 0.024),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: availableHeight * 0.016,
                                      horizontal: 16,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Username is required';
                                    }
                                    return null;
                                  },
                                ),

                                SizedBox(height: availableHeight * 0.02),

                                // Password
                                Text(
                                  'Password',
                                  style: TextStyle(
                                    fontSize: availableHeight * 0.018,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: availableHeight * 0.008),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _login(),
                                  style: TextStyle(
                                      fontSize: availableHeight * 0.02),
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    hintStyle: TextStyle(
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.6),
                                      fontSize: availableHeight * 0.019,
                                    ),
                                    prefixIcon: Icon(Icons.lock_outline,
                                        size: availableHeight * 0.024),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: availableHeight * 0.024,
                                        color: AppColors.textSecondary,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: availableHeight * 0.016,
                                      horizontal: 16,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password is required';
                                    }
                                    return null;
                                  },
                                ),

                                SizedBox(height: availableHeight * 0.028),

                                // Sign in button — sized to fit its own content
                                // (icon + text + theme padding) rather than a
                                // fixed proportional height, which was clipping
                                // the descenders of "Sign In" on shorter screens.
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(
                                          vertical: availableHeight * 0.02),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 3,
                                    ),
                                    child: _isLoading
                                        ? SizedBox(
                                            height: availableHeight * 0.026,
                                            width: availableHeight * 0.026,
                                            child:
                                                const CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.login_rounded,
                                                  size:
                                                      availableHeight * 0.024),
                                              SizedBox(
                                                  width: size.width * 0.02),
                                              Text(
                                                'Sign In',
                                                style: TextStyle(
                                                  fontSize:
                                                      availableHeight * 0.022,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 12),
                                Center(
                                  child: TextButton(
                                    onPressed: _showForgotPasswordDialog,
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),

                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
