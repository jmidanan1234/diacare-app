import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';
import '../../models/notification_model.dart';
import '../patients/patient_profile_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final notifications = provider.notifications;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Alerts'),
            actions: [
              if (provider.unreadNotifCount > 0)
                TextButton(
                  onPressed: () => provider.markAllNotificationsRead(),
                  child: const Text(
                    'Mark All Read',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: provider.loadAll,
            child: notifications.isEmpty
                ? ListView(
                    padding: const EdgeInsets.only(top: 80),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'No alerts',
                        subtitle: 'High-risk alerts and visit reminders will appear here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _NotificationCard(
                      notification: notifications[i],
                      onTap: () {
                        provider.markNotificationRead(notifications[i].id);
                        final patientId = notifications[i].patientId;
                        final all = provider.patients;
                        final match = all.where((p) => p.id == patientId);
                        if (match.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PatientProfileScreen(patient: match.first)),
                          );
                        }
                      },
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

Color get _color =>
      notification.type == 'high_risk' ? AppColors.highRisk
          : notification.type == 'high_bp' ? AppColors.highRisk
          : notification.type == 'flagged' ? AppColors.accent
          : AppColors.warning;

 IconData get _icon =>
      notification.type == 'high_risk' ? Icons.warning_rounded
          : notification.type == 'high_bp' ? Icons.monitor_heart_rounded
          : notification.type == 'flagged' ? Icons.flag_rounded
          : notification.type == 'at_risk' ? Icons.info_rounded
          : Icons.schedule_rounded;

  // "HIGHLY AT RISK" matches the wording used everywhere else in the app.
  String get _typeLabel =>
      notification.type == 'high_risk' ? 'HIGHLY AT RISK'
          : notification.type == 'high_bp' ? 'HIGH BLOOD PRESSURE'
          : notification.type == 'flagged' ? 'FLAGGED FOR FOLLOW-UP'
          : notification.type == 'at_risk' ? 'AT RISK'
          : 'VISIT OVERDUE';

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : _color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        boxShadow: cardShadow(strength: notification.isRead ? 1.2 : 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, color: _color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _typeLabel,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _color,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (!notification.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.patientName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        notification.message,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTime(notification.createdAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM d, y').format(dt);
  }
}
