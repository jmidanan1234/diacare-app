import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/sync_service.dart';
import '../widgets/sync_prompt_dialog.dart';
import 'dashboard/dashboard_screen.dart';
import 'patients/patient_list_screen.dart';
import 'records/records_screen.dart';
import 'notifications/notifications_screen.dart';
import 'profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  StreamSubscription<bool>? _connectivitySub;
  bool _promptShowing = false;

  static const _screens = [
    DashboardScreen(),
    PatientListScreen(),
    RecordsScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _connectivitySub = SyncService().onConnectivityRestored.listen((_) {
      _checkAndPromptSync();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await SyncService().isOnline && mounted) {
        await _checkAndPromptSync();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _checkAndPromptSync() async {
    if (!mounted || _promptShowing) return;
    final provider = context.read<AppProvider>();
    final bhwId = provider.currentUser?.id;
    if (bhwId == null) return;

    final count = await SyncService().getUnsyncedCount(bhwId);
    if (count > 0 && mounted) {
      _promptShowing = true;
      await SyncPromptDialog.show(context, count);
      _promptShowing = false;
    } else if (mounted) {
      // A worker with no uploads may still have newly assigned RHU patients
      // or alerts waiting. Pull them on sign-in and after reconnecting.
      await provider.syncAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: IndexedStack(
            index: provider.selectedTab,
            children: _screens,
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 12,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: provider.selectedTab,
              onTap: provider.setTab,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard_rounded),
                  label: 'Dashboard',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline_rounded),
                  activeIcon: Icon(Icons.people_rounded),
                  label: 'Patients',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.assignment_outlined),
                  activeIcon: Icon(Icons.assignment_rounded),
                  label: 'Records',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: provider.unreadNotifCount > 0,
                    label: Text('${provider.unreadNotifCount}'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: provider.unreadNotifCount > 0,
                    label: Text('${provider.unreadNotifCount}'),
                    child: const Icon(Icons.notifications_rounded),
                  ),
                  label: 'Alerts',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded),
                  activeIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
