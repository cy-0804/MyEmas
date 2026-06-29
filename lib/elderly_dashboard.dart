import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'medication_missed_checker.dart';
import 'health_dashboard_view.dart';
import 'medication_dashboard_view.dart';
import 'schedule_dashboard_view.dart';
import 'add_edit_schedule_screen.dart';
import 'voice_search_helper.dart';
import 'dart:async';
import 'sos_active_screen.dart';
import 'elderly_settings_screen.dart';
import 'sos_notification_service.dart';
import 'package:permission_handler/permission_handler.dart';

const _kPrimary = Color(0xFF51A77B);
const _kBlue = Color(0xFF00539E);
const _kBg = Color(0xFFF6F8FA);

class ElderlyDashboard extends StatefulWidget {
  const ElderlyDashboard({super.key});
  @override
  State<ElderlyDashboard> createState() => _ElderlyDashboardState();
}

class _ElderlyDashboardState extends State<ElderlyDashboard> {
  int _selectedIndex = 0;
  String _userName = 'User';
  HealthRecord? _latestRecord;

  // SOS State
  bool _sosHolding = false;
  double _sosProgress = 0.0;
  static const int _sosDurationMs = 3000;
  Timer? _periodicTimer;
  DateTime? _lastPromptTime;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _requestCriticalPermissions();
    _periodicTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await MedicationMissedChecker.checkAndMarkMissed(uid);
      }
      await _checkHealthReminder();
    });
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestCriticalPermissions() async {
    // Request all critical permissions for SOS upfront so the app doesn't crash or block during an emergency.
    await [Permission.phone, Permission.sms, Permission.location].request();
  }

  Future<void> _checkHealthReminder() async {
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return;

      final elRes = await db
          .from('elderly')
          .select('health_record_time')
          .eq('user_id', uid)
          .maybeSingle();
      if (elRes == null || elRes['health_record_time'] == null) return;

      final timeStr = elRes['health_record_time'] as String;
      final parts = timeStr.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;

      final now = DateTime.now();
      final recordTime = DateTime(now.year, now.month, now.day, hour, minute);

      if (now.isAfter(recordTime)) {
        // Check if there is a record for today
        final startOfDay = DateTime(
          now.year,
          now.month,
          now.day,
        ).toUtc().toIso8601String();
        final hrRes = await db
            .from('health_record')
            .select('record_id')
            .eq('elderly_id', uid)
            .gte('recorded_at', startOfDay)
            .limit(1)
            .maybeSingle();

        if (hrRes == null) {
          // No record today!
          // 1. Prompt elderly every 15 mins
          if (_lastPromptTime == null ||
              now.difference(_lastPromptTime!).inMinutes >= 15) {
            _lastPromptTime = now;
            SosNotificationService().showMedicationNotification(
              elderlyName: _userName,
              title: 'Health Data Reminder',
              summaryText: 'Daily Health Log',
              message: 'Please remember to log your health data for today!',
            );
          }

          // 2. Alert caregiver if skipped (e.g. > 1 hour past recordTime)
          if (now.difference(recordTime).inMinutes > 60) {
            // Check if we already sent alert today
            final alertRes = await db
                .from('emergency_logs')
                .select('alert_id')
                .eq('status', 'health_missed')
                .gte('timestamp', startOfDay)
                .limit(1)
                .maybeSingle();
            if (alertRes == null) {
              // Get caregiver link
              final linkRes = await db
                  .from('care_link')
                  .select('link_id')
                  .eq('elderly_id', uid)
                  .limit(1)
                  .maybeSingle();
              if (linkRes != null) {
                await db.from('emergency_logs').insert({
                  'link_id': linkRes['link_id'],
                  'status': 'health_missed',
                  'location': '{"address":"Health Data Missed"}',
                  'timestamp': DateTime.now().toUtc().toIso8601String(),
                });
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Health reminder check error: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return;

      // Run the retroactive missed medication check
      await MedicationMissedChecker.checkAndMarkMissed(uid);

      // Load user name
      final userData = await Supabase.instance.client
          .from('users')
          .select('fullname')
          .eq('user_id', uid)
          .maybeSingle();

      // Load latest health record
      final healthRes = await Supabase.instance.client
          .from('health_record')
          .select()
          .eq('elderly_id', uid)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (userData != null && userData['fullname'] != null) {
            final full = userData['fullname'] as String;
            _userName = full.split(' ').first;
          }
          _latestRecord = healthRes != null
              ? HealthRecord.fromMap(healthRes)
              : null;
        });
      }
    } catch (e) {
      debugPrint('Dashboard load error: $e');
    }
  }

  void _openAddHealthRecord() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditHealthRecordScreen(elderlyId: uid),
      ),
    );
    _loadUserData();
  }

  void _openAddMedicine() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEditMedicineScreen()),
    );
  }

  void _openAddSchedule() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEditScheduleScreen()),
    );
    if (result == true) {
      _loadUserData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            VoiceSearchBar(
              onCommand: (cmd) {
                if (cmd.contains('medicine') ||
                    cmd.contains('medicat') ||
                    cmd.contains('pill')) {
                  if (cmd.contains('add')) {
                    _openAddMedicine();
                  } else {
                    setState(() => _selectedIndex = 2);
                  }
                } else if (cmd.contains('health') ||
                    cmd.contains('record') ||
                    cmd.contains('blood')) {
                  if (cmd.contains('add')) {
                    _openAddHealthRecord();
                  } else {
                    setState(() => _selectedIndex = 1);
                  }
                } else if (cmd.contains('schedule') ||
                    cmd.contains('calendar') ||
                    cmd.contains('appointment') ||
                    cmd.contains('event')) {
                  if (cmd.contains('add') ||
                      cmd.contains('new') ||
                      cmd.contains('create')) {
                    _openAddSchedule();
                  } else {
                    setState(() => _selectedIndex = 3);
                  }
                } else if (cmd.contains('home') ||
                    cmd.contains('dashboard') ||
                    cmd.contains('main')) {
                  setState(() => _selectedIndex = 0);
                }
              },
            ),
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildHomeTab(),
                      const HealthDashboardView(),
                      const MedicationDashboardView(),
                      const ScheduleDashboardView(),
                      const ElderlySettingsScreen(),
                    ],
                  ),
                  // SOS Floating Button
                  Positioned(right: 16, bottom: 80, child: _buildSosButton()),
                  // Bottom Nav
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildBottomNav(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Home Tab ────────────────────────────────────────────────────────────────
  Widget _buildHomeTab() {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good Morning'
        : now.hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── top bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Hello, ',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF27252E),
                              fontFamily: 'League Spartan',
                            ),
                          ),
                          TextSpan(
                            text: _userName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _kBlue,
                              fontFamily: 'League Spartan',
                            ),
                          ),
                          const TextSpan(
                            text: ' 👋',
                            style: TextStyle(fontSize: 22),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Date card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3BBA8A), Color(0xFF0C6745)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _kPrimary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE').format(now),
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d MMMM yyyy').format(now),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    DateFormat('hh:mm a').format(now),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Quick Actions ──
          _buildSectionHeader('Quick Actions'.tr()),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildQuickAction(
                  'Health Data'.tr(),
                  Icons.favorite_rounded,
                  const Color(0xFFFFEBEE),
                  const Color(0xFFF44336),
                  _openAddHealthRecord,
                ),
                _buildQuickAction(
                  'Log Medicine'.tr(),
                  Icons.medication_liquid,
                  const Color(0xFFE3F2FD),
                  _kBlue,
                  _openAddMedicine,
                ),
                _buildQuickAction(
                  'Schedules'.tr(),
                  Icons.calendar_today_rounded,
                  const Color(0xFFE8F5E9),
                  const Color(0xFF4CAF50),
                  _openAddSchedule,
                ),
                _buildQuickAction(
                  'Settings'.tr(),
                  Icons.settings_rounded,
                  const Color(0xFFF3E5F5), // Light purple background
                  const Color(0xFF9C27B0), // Purple icon
                  () => setState(() => _selectedIndex = 4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    String title,
    IconData icon,
    Color bg,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 42, color: color),
            const SizedBox(width: 24),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.5),
              size: 30,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'League Spartan',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF27252E),
            ),
          ),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Text(
                'View All'.tr(),
                style: const TextStyle(
                  color: _kPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Settings tab is now handled by ElderlySettingsScreen

  // ─── SOS Button ──────────────────────────────────────────────────────────────
  Widget _buildSosButton() {
    return GestureDetector(
      onLongPressStart: (_) {
        setState(() {
          _sosHolding = true;
          _sosProgress = 0.0;
        });
        _runSosCountdown();
      },
      onLongPressEnd: (_) {
        if (_sosProgress < 1.0) {
          // Released too early — cancel
          setState(() {
            _sosHolding = false;
            _sosProgress = 0.0;
          });
        }
      },
      onLongPressCancel: () {
        setState(() {
          _sosHolding = false;
          _sosProgress = 0.0;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _sosHolding ? 80 : 70,
        height: _sosHolding ? 80 : 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: _sosHolding ? 0.5 : 0.25),
              blurRadius: _sosHolding ? 24 : 16,
              spreadRadius: _sosHolding ? 8 : 4,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Countdown ring
            if (_sosHolding)
              SizedBox(
                width: 78,
                height: 78,
                child: CircularProgressIndicator(
                  value: _sosProgress,
                  strokeWidth: 4,
                  color: Colors.red,
                  backgroundColor: Colors.red.withValues(alpha: 0.2),
                ),
              ),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFF9D5C), Color(0xFFFF5252)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'SOS'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'Hold'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _runSosCountdown() async {
    const steps = 60;
    final stepDuration = Duration(milliseconds: _sosDurationMs ~/ steps);

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(stepDuration);
      if (!_sosHolding || !mounted) return; // Cancelled
      setState(() => _sosProgress = i / steps);
    }

    // 3 seconds complete — trigger SOS
    if (!mounted) return;
    setState(() {
      _sosHolding = false;
      _sosProgress = 0.0;
    });
    _triggerSos();
  }

  Future<void> _triggerSos() async {
    // Navigate to SOS active screen first
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SosActiveScreen()),
    );
  }

  // ─── Bottom Nav ──────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(0, Icons.home_rounded, 'Dashboard'.tr()),
          _navItem(1, Icons.monitor_heart_rounded, 'Health Data'.tr()),
          _navItem(2, Icons.medication_liquid, 'Medications'.tr()),
          _navItem(3, Icons.calendar_today, 'Schedules'.tr()),
          _navItem(4, Icons.settings_rounded, 'Settings'.tr()),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final sel = _selectedIndex == index;
    final color = sel ? _kBlue : Colors.grey.shade400;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        if (index == 0) _loadUserData(); // Refresh Home tab when coming back
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: sel
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: sel ? _kBlue.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
