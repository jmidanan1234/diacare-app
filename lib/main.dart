import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'providers/app_provider.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'utils/theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/force_change_password_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // App runs in offline mode backed by SQLite
  }

  unawaited(FCMService().init());

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const DiaCareApp(),
    ),
  );
}

class DiaCareApp extends StatelessWidget {
  const DiaCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiaCare',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const _SplashRouter(),
    );
  }
}

class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _dots;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _init();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _dots.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Small delay for splash feel
    await Future.delayed(const Duration(milliseconds: 2000));

    final auth = AuthService();
    final hasSession = await auth.restoreSession();

    if (!mounted) return;

    if (hasSession) {
      if (auth.currentUser?.mustChangePassword ?? false) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ForceChangePasswordScreen()),
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
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  Widget _buildCircularDotsLoader() {
    const dotCount = 8;
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, child) {
        return Transform.rotate(
          angle: _dots.value * 2 * math.pi,
          child: child,
        );
      },
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: List.generate(dotCount, (i) {
            final angle = (i / dotCount) * 2 * math.pi;
            final t = i / dotCount; // 0 (trail) -> ~1 (lead)
            const radius = 13.0;
            final dotSize = 4.0 + (t * 3.5);
            return Transform.translate(
              offset: Offset(
                radius * math.cos(angle),
                radius * math.sin(angle),
              ),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.25 + (t * 0.75)),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Splash background now matches the app's actual brand color
          // (same teal gradient used on Login/Dashboard) instead of the
          // previous near-white tint.
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppGradients.hero),
          ),
          // Soft decorative blobs — recolored for a dark surface. White
          // gives a neutral highlight; coral is the app's own accent.
          // Same soft-circle idiom used on Login and the Dashboard header,
          // so every "hero" surface in the app reads as one design family.
          Positioned(
            top: -size.width * 0.28,
            right: -size.width * 0.32,
            child: Container(
              width: size.width * 0.75,
              height: size.width * 0.75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Soft decorative blob — bottom left (coral accent)
          Positioned(
            bottom: -size.width * 0.32,
            left: -size.width * 0.35,
            child: Container(
              width: size.width * 0.9,
              height: size.width * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.18),
                    AppColors.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Content
          Align(
            alignment: const Alignment(0, -0.08),
            child: FadeTransition(
              opacity: _entrance,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1.0).animate(
                  CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // White backdrop chip behind the logo — the logo's own
                    // green tones sit on neutral white rather than directly
                    // on the teal background, so contrast holds regardless
                    // of how close the two greens/teals might otherwise
                    // read. Same technique already used on the Login screen.
                    Container(
                      width: 88,
                      height: 88,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/logo_splash.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'DiaCare',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Loading indicator — pinned near the bottom of the screen
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * 0.12,
            child: Center(
              child: FadeTransition(
                opacity: _entrance,
                child: _buildCircularDotsLoader(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
