import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color tokens.
///
/// `primary` and `accent` are the app's fixed brand colors (from the DiaCare
/// logo) and are intentionally left untouched — everything else in this
/// palette is a supporting tint built around them, not a replacement.
class AppColors {
  static const primary = Color(0xFF0B5357); // Logo teal-green — fixed brand color
  static const primaryLight = Color(0xFF13767C);
  static const primaryDark = Color(0xFF063638);
  static const primaryDeep = Color(0xFF084649); // gradient end-stop, between light and dark
  static const accent = Color(0xFFF4624C); // Logo coral-orange — fixed brand color

  // Soft tints of the brand color, used for hero surfaces, icon chips, and
  // tinted section backgrounds instead of flat white/grey everywhere.
  static const primarySoft = Color(0xFFEAF3F2);
  static const primarySofter = Color(0xFFF4F9F8);
  static const accentSoft = Color(0xFFFDEBE8);

  static const background = Color(0xFFF6F8F8);
  static const surface = Colors.white;

  static const error = Color(0xFFE0453B);
  static const warning = Color(0xFFF08C1D);
  static const success = Color(0xFF2E9E51);

  static const highRisk = Color(0xFFE0453B);
  static const moderateRisk = Color(0xFFF08C1D);
  static const normalRisk = Color(0xFF2E9E51);

  static const textPrimary = Color(0xFF16232A);
  static const textSecondary = Color(0xFF66757C);
  static const textMuted = Color(0xFF9AA6AB);

  // Trend badge colors
  static const trendStable = Color(0xFF6B7280);
  static const trendStableBg = Color(0xFFF3F4F6);

  static const divider = Color(0xFFE6ECEA);
  static const cardBorder = Color(0xFFEBF0EF);

  /// A brand-tinted shadow (instead of flat black/grey) is the app's one
  /// quiet recurring signature — every card and elevated surface uses this
  /// rather than a generic shadow color.
  static Color shadow({double opacity = 0.06}) => primaryDark.withValues(alpha: opacity);
}

/// Reusable gradients — kept to a single deliberate spot (the dashboard hero
/// and primary buttons) rather than scattered across every surface.
class AppGradients {
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDeep],
  );

  static const heroSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primarySoft, AppColors.primarySofter],
  );
}

/// Shared radius scale so cards, buttons, and inputs stay visually consistent.
class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
}

/// Shared spacing scale — every screen pads/gaps using one of these instead
/// of ad-hoc numbers, so density feels consistent from screen to screen.
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
}

/// A single, reusable "icon inside a soft tinted circle" treatment for empty
/// states — used everywhere a list has nothing to show, so every empty
/// state across the app looks like one deliberate design rather than a
/// bare grey icon dropped on the page.
/// A section header ("Overview", "Quick Actions", etc.) hard-clipped to an
/// exact height. Some fonts (Poppins included) bake extra vertical leading
/// into the font file itself, above and below the visible glyphs, in a way
/// that line-height/strut tuning alone doesn't fully remove. Clipping to a
/// fixed box sidesteps that entirely instead of continuing to fight it.
class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: 17,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? color;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: c.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A shimmering placeholder block used to build skeleton loaders — feels far
/// less jarring than a bare spinner for list-shaped content (dashboard
/// cards, patient rows) that we already know the rough shape of.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppColors.divider,
              AppColors.cardBorder,
              _controller.value,
            ),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// A soft, brand-tinted card shadow — the one recurring elevation treatment
/// used everywhere instead of ad-hoc grey shadows or plain borders.
List<BoxShadow> cardShadow({double strength = 1.0}) => [
      BoxShadow(
        color: AppColors.shadow(opacity: 0.05 * strength),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: AppColors.shadow(opacity: 0.03 * strength),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];

class AppTheme {
  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
    );

    // Poppins for headings/titles — warm and approachable without being
    // too playful, and a proven pairing for health/community apps — with
    // Inter for body/data since it stays highly legible at the small
    // sizes this app leans on for vitals and tables.
    const headingFont = GoogleFonts.poppins;
    const bodyFont = GoogleFonts.inter;

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: headingFont(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        backgroundColor: Colors.white,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: bodyFont(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: bodyFont(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.cardBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.cardBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: bodyFont(color: AppColors.textSecondary, fontSize: 14),
        floatingLabelStyle: bodyFont(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
        hintStyle: bodyFont(color: AppColors.textMuted, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          elevation: 2,
          shadowColor: AppColors.primary.withValues(alpha: 0.35),
          textStyle: bodyFont(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: bodyFont(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: bodyFont(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primarySoft,
        labelStyle: bodyFont(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
      textTheme: TextTheme(
        headlineLarge: headingFont(
            color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -0.5),
        headlineMedium: headingFont(
            color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 22, letterSpacing: -0.3),
        headlineSmall: headingFont(
            color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.2),
        titleLarge: headingFont(
            color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16, height: 1.0),
        titleMedium: bodyFont(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
        bodyLarge: bodyFont(color: AppColors.textPrimary, fontSize: 15, height: 1.4),
        bodyMedium: bodyFont(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        labelLarge: bodyFont(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}
