import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/user_model.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/shared_widgets.dart';
import '../records/add_record_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final user = provider.currentUser;
        final highRiskPatients = provider.patients
            .where((p) => p.riskLevel == AppConstants.riskHigh)
            .toList();

        return Scaffold(
          backgroundColor: AppColors.background,
          // Hero header now lives outside the loading/loaded switch — it's
          // built exactly once and stays mounted the whole time the
          // Dashboard tab exists, so its wave animation only ever starts
          // once instead of being torn down and rebuilt when isLoading
          // flips from true to false right after the screen first opens.
          body: Column(
            children: [
              _DashboardHeroHeader(user: user, lastSyncTime: provider.lastSyncTime),
              Expanded(
                child: provider.isLoading
                    ? const _DashboardSkeleton()
                    : RefreshIndicator(
                        onRefresh: provider.loadAll,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // High risk alert
                              if (highRiskPatients.isNotEmpty) ...[
                          Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              boxShadow: cardShadow(),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.highRisk.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.warning_amber_rounded,
                                        color: AppColors.highRisk, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${highRiskPatients.length} patient${highRiskPatients.length > 1 ? "s" : ""} need immediate attention',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          highRiskPatients.map((p) => p.fullName).join(', '),
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Overview — placed first (right after alerts): a BHW
                        // opening the Dashboard is checking the state of
                        // things before deciding what to do about it, so
                        // situational numbers come before action shortcuts.
                        const SectionHeader('Overview'),
                        const SizedBox(height: 0),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.3,
                          children: [
                            SummaryCard(
                              title: 'Total Patients',
                              value: '${provider.totalPatients}',
                              icon: Icons.people_rounded,
                              color: AppColors.primary,
                              onTap: () => provider.setTab(1),
                            ),
                            SummaryCard(
                              title: 'Highly At Risk',
                              value: '${provider.highRiskCount}',
                              icon: Icons.warning_rounded,
                              color: AppColors.highRisk,
                              onTap: () {
                                provider.setPendingPatientListFilter(AppConstants.riskHigh);
                                provider.setTab(1);
                              },
                            ),
                            SummaryCard(
                              title: 'Not Visited (7+ days)',
                              value: '${provider.unvisitedCount}',
                              icon: Icons.schedule_rounded,
                              color: AppColors.warning,
                              onTap: () {
                                provider.setPendingPatientListFilter('NotVisited');
                                provider.setTab(1);
                              },
                            ),
                            SummaryCard(
                              title: 'Unread Alerts',
                              value: '${provider.unreadNotifCount}',
                              icon: Icons.notifications_rounded,
                              color: AppColors.accent,
                              onTap: () => provider.setTab(3),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Quick actions
                        const SectionHeader('Quick Actions'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickAction(
                                label: 'Add Record',
                                icon: Icons.add_circle_outline_rounded,
                                color: AppColors.primary,
                                onTap: () {
                                  if (provider.patients.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No patients assigned yet.')),
                                    );
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AddRecordScreen(patients: provider.patients),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickAction(
                                label: 'View Patients',
                                icon: Icons.people_alt_outlined,
                                color: AppColors.primaryLight,
                                onTap: () => provider.setTab(1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Recent records
                        if (provider.recentRecords.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SectionHeader('Recent Records'),
                              TextButton(
                                onPressed: () => provider.setTab(2),
                                child: const Text('View All', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...provider.recentRecords.take(5).map((r) {
                            final matches = provider.patients.where((p) => p.id == r.patientId);
                            final patientName = matches.isNotEmpty ? matches.first.fullName : 'Unknown patient';
                            return _RecentRecordRow(
                              patientName: patientName,
                              record: r,
                              onTap: () {
                                provider.setTab(1);
                              },
                            );
                          }),
                        ],

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The Dashboard's top header — replaces the old flat AppBar + separate
/// hero card with one full-bleed surface that carries the app's identity,
/// the day's greeting, and sync status together. Decorative blobs echo the
/// same soft-circle treatment used on the splash screen (same design
/// family, not a new one-off), and the large translucent blood-drop mark
/// is this app's own motif — a glucose/blood-monitoring reference specific
/// to DiaCare, not borrowed from any reference image.
class _DashboardHeroHeader extends StatelessWidget {
  final UserModel? user;
  final String? lastSyncTime;

  const _DashboardHeroHeader({required this.user, required this.lastSyncTime});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppGradients.hero),
        child: Stack(
          children: [
            // Soft decorative blobs — same idiom as the splash screen,
            // recolored for a dark surface instead of a light one.
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 170,
                height: 170,
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
            Positioned(
              bottom: -55,
              left: -35,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.20),
                      AppColors.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // DiaCare's own watermark — the actual logo, rendered as a
            // translucent white silhouette rather than a generic icon.
            Positioned(
              right: -18,
              bottom: -14,
              child: Image.asset(
                'assets/images/logo.png',
                width: 128,
                height: 128,
                color: Colors.white.withValues(alpha: 0.10),
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand row — replaces the old flat AppBar title. Logo
                    // sits on a white backdrop chip, same technique as
                    // Login/Splash, so it stays crisp regardless of size.
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'DiaCare',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                lastSyncTime != null ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                lastSyncTime != null ? 'Synced' : 'Not synced',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user != null ? 'Hello, ${user!.firstName}' : 'Hello!',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _WavingHand(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 13, color: Colors.white.withValues(alpha: 0.75)),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRecordRow extends StatelessWidget {  final String patientName;
  final dynamic record;
  final VoidCallback onTap;

  const _RecentRecordRow({
    required this.patientName,
    required this.record,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: cardShadow(strength: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.medical_services_outlined, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Glucose: ${record.bloodGlucose.toStringAsFixed(0)} • BP: ${record.bloodPressure}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                RiskBadge(riskLevel: record.riskLevel, compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton loading state — mirrors the real layout's shape (hero, quick
/// actions, summary grid, recent-records list) so the screen doesn't jump
/// around once real content arrives, and feels less like a dead pause than
/// a bare spinner would on the very first screen of every session.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 85, height: 16),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.3,
            children: const [
              SkeletonBox(borderRadius: BorderRadius.all(Radius.circular(18))),
              SkeletonBox(borderRadius: BorderRadius.all(Radius.circular(18))),
              SkeletonBox(borderRadius: BorderRadius.all(Radius.circular(18))),
              SkeletonBox(borderRadius: BorderRadius.all(Radius.circular(18))),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(width: 110, height: 16),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 56, borderRadius: BorderRadius.all(Radius.circular(18)))),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 56, borderRadius: BorderRadius.all(Radius.circular(18)))),
            ],
          ),
          const SizedBox(height: 24),
          const SkeletonBox(width: 130, height: 16),
          const SizedBox(height: 10),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SkeletonBox(height: 56, borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small waving-hand greeting animation next to "Hello, {name}". Waves a
/// few times on load (3 full back-and-forth motions), then settles at rest
/// — a continuous forever-loop would be distracting for a screen a BHW
/// checks repeatedly during real work, so this greets once and stops.
class _WavingHand extends StatefulWidget {
  const _WavingHand();

  @override
  State<_WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<_WavingHand> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _swing;

  static const int _totalLegs = 6; // 3 full forward+back waves

  int _legsCompleted = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _swing = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.addStatusListener(_onStatus);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed && status != AnimationStatus.dismissed) return;
    _legsCompleted++;
    if (_legsCompleted >= _totalLegs) return;
    if (status == AnimationStatus.completed) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _swing,
      builder: (context, child) {
        // Oscillates roughly -14deg to +9deg, pivoting from the base of
        // the hand (like a wrist) rather than its own center.
        final angle = -0.25 + (_swing.value * 0.40);
        return Transform.rotate(
          angle: angle,
          alignment: Alignment.bottomCenter,
          child: child,
        );
      },
      child: Icon(
        Icons.waving_hand,
        size: 22,
        color: Colors.white.withValues(alpha: 0.75),
      ),
    );
  }
}
