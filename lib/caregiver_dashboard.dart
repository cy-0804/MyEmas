import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'medication_missed_checker.dart';
import 'login_screen.dart';
import 'caregiver_scan_qr_screen.dart';
import 'caregiver_elderly_detail_screen.dart';
import 'sos_notification_service.dart';
import 'location_search_field.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── colour tokens ────────────────────────────────────────────────────────────
const _kBlue = Color(0xFF00539E);
const _kGreen = Color(0xFF51A77B);
const _kDark = Color(0xFF1A1D2E);
const _kGrey = Color(0xFF6C7278);
const _kBg = Color(0xFFF0F4F8);
const _kCard = Colors.white;

// ─── risk helpers ─────────────────────────────────────────────────────────────
Color _riskColor(String? r) {
  switch (r) {
    case 'high':
      return const Color(0xFFD32F2F);
    case 'medium':
      return const Color(0xFFF57C00);
    default:
      return const Color(0xFF388E3C);
  }
}

Color _riskBg(String? r) {
  switch (r) {
    case 'high':
      return const Color(0xFFFFEBEE);
    case 'medium':
      return const Color(0xFFFFF3E0);
    default:
      return const Color(0xFFE8F5E9);
  }
}

String _riskLabel(String? r) {
  switch (r) {
    case 'high':
      return 'HIGH RISK'.tr();
    case 'medium':
      return 'MEDIUM RISK'.tr();
    default:
      return 'LOW RISK'.tr();
  }
}

// ─── LinkedElderly model ─────────────────────────────────────────────────────
class LinkedElderly {
  final String elderlyId;
  final String name;
  final String? gender;
  final String? phone;
  final String? email;
  final String? bloodType;
  final String? chronicCondition;
  final String? latestRisk;
  final String? latestBP;
  final int? latestHR;
  final double? latestGlucose;
  final double? latestTemp;

  const LinkedElderly({
    required this.elderlyId,
    required this.name,
    this.gender,
    this.phone,
    this.email,
    this.bloodType,
    this.chronicCondition,
    this.latestRisk,
    this.latestBP,
    this.latestHR,
    this.latestGlucose,
    this.latestTemp,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// CaregiverDashboard
// ═════════════════════════════════════════════════════════════════════════════
class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  int _navIndex = 0;
  List<LinkedElderly> _linked = [];
  bool _loading = true;
  String? _caregiverName;
  Timer? _refreshTimer;
  Timer? _sosPollTimer; // Fast-polling for SOS alerts (every 10s)

  // SOS Alert State
  Map<String, dynamic>? _activeSosAlert;
  RealtimeChannel? _sosChannel;
  RealtimeChannel? _medLogChannel;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadAll();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadAll(),
    );
    // Fast-poll every 10s specifically for SOS alerts as a realtime fallback
    _sosPollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkActiveSos(),
    );
    _subscribeToRealtimeAlerts();
    SosNotificationService().initialize();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sosPollTimer?.cancel();
    _sosChannel?.unsubscribe();
    _medLogChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return;

      // Caregiver profile
      final userRow = await db
          .from('users')
          .select('fullname')
          .eq('user_id', uid)
          .maybeSingle();
      _caregiverName = userRow?['fullname'] as String? ?? 'Caregiver'.tr();

      // Ensure caregiver row
      final cgRow = await db
          .from('caregiver')
          .select('user_id')
          .eq('user_id', uid)
          .maybeSingle();
      if (cgRow == null) await db.from('caregiver').insert({'user_id': uid});

      // Fetch linked elderly
      final links = await db
          .from('care_link')
          .select('elderly_id')
          .eq('caregiver_id', uid);

      final List<LinkedElderly> result = [];
      for (final lk in (links as List)) {
        final eid = lk['elderly_id'] as String;

        // Run missed medication check for this elderly
        await MedicationMissedChecker.checkAndMarkMissed(eid);

        // User info
        final uRow = await db
            .from('users')
            .select('fullname, gender, phone_num, email')
            .eq('user_id', eid)
            .maybeSingle();
        // Elderly health info
        final eRow = await db
            .from('elderly')
            .select('blood_type, chronic_condition')
            .eq('user_id', eid)
            .maybeSingle();
        // Latest health record
        final hRow = await db
            .from('health_record')
            .select(
              'record_id, blood_pressure, heart_rate, glucose_level, temperature',
            )
            .eq('elderly_id', eid)
            .order('recorded_at', ascending: false)
            .limit(1)
            .maybeSingle();

        String? risk;
        if (hRow != null) {
          final rRow = await db
              .from('health_risk_assessment')
              .select('risk_level')
              .eq('record_id', hRow['record_id'] as String)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          risk = rRow?['risk_level'] as String?;
        }

        result.add(
          LinkedElderly(
            elderlyId: eid,
            name: uRow?['fullname'] as String? ?? 'Unknown'.tr(),
            gender: uRow?['gender'] as String?,
            phone: uRow?['phone_num'] as String?,
            email: uRow?['email'] as String?,
            bloodType: eRow?['blood_type'] as String?,
            chronicCondition: eRow?['chronic_condition'] as String?,
            latestRisk: risk,
            latestBP: hRow?['blood_pressure'] as String?,
            latestHR: hRow?['heart_rate'] as int?,
            latestGlucose: (hRow?['glucose_level'] as num?)?.toDouble(),
            latestTemp: (hRow?['temperature'] as num?)?.toDouble(),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _linked = result;
          _loading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('CaregiverDashboard load error: $e\n$stack');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'.tr(), maxLines: 3),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    // Also check active SOS
    await _checkActiveSos();
  }

  Future<void> _checkActiveSos() async {
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return;

      // Get all linked elderly IDs
      final links = await db
          .from('care_link')
          .select('elderly_id')
          .eq('caregiver_id', uid);
      final elderlyIds = (links as List)
          .map((l) => l['elderly_id'] as String)
          .toList();
      if (elderlyIds.isEmpty) return;

      // Check for any SOS with call_status = 'unanswered' from linked elderly
      final sos = await db
          .from('emergency_logs')
          .select('alert_id, elderly_id, location, timestamp, call_status')
          .eq('status', 'active')
          .inFilter('elderly_id', elderlyIds)
          .order('timestamp', ascending: false)
          .limit(1)
          .maybeSingle();

      if (sos != null) {
        final uRes = await db
            .from('users')
            .select('fullname')
            .eq('user_id', sos['elderly_id'])
            .maybeSingle();
        final name = uRes?['fullname'] as String? ?? 'Patient'.tr();
        String location = 'Unknown location'.tr();
        String? mapUrl;
        try {
          final loc = jsonDecode(sos['location'] as String);
          location = loc['address'] ?? '${loc['lat']}, ${loc['lng']}';
          if (loc['lat'] != null && loc['lng'] != null) {
            mapUrl = 'https://maps.google.com/?q=${loc['lat']},${loc['lng']}';
          }
        } catch (_) {}

        if (mounted) {
          debugPrint('SOS: Found active SOS! Displaying overlay...');
          setState(
            () => _activeSosAlert = {
              ...sos,
              'name': name,
              'parsed_location': location,
            },
          );
          // Show in-app overlay
          SosNotificationService().showSosOverlay(
            context: context,
            elderlyName: name,
            location: location,
            mapUrl: mapUrl,
            alertId: sos['alert_id'] as String,
            onConfirm: _respondToSos,
          );
          // Start repeating Android system notification
          SosNotificationService().startRepeatNotification(
            elderlyName: name,
            location: location,
            alertId: sos['alert_id'] as String,
          );
        }
      } else {
        if (mounted) {
          debugPrint('SOS: No active SOS found.');
          setState(() => _activeSosAlert = null);
          SosNotificationService().dismissSosNotification();
        }
      }
    } catch (e) {
      debugPrint('SOS check error: $e');
    }
  }

  void _subscribeToRealtimeAlerts() {
    final db = Supabase.instance.client;

    // 1. SOS Alerts
    _sosChannel = db
        .channel('emergency_logs_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'emergency_logs',
          callback: (payload) async {
            final newLog = payload.newRecord;

            // ── Handle new active SOS alert ──────────────────────────────────
            if (newLog['status'] == 'active' &&
                payload.eventType == PostgresChangeEvent.insert) {
              debugPrint('SOS: Realtime detected NEW active SOS insert!');
              final elderlyId = newLog['elderly_id'] as String?;
              if (elderlyId != null &&
                  _linked.any((le) => le.elderlyId == elderlyId)) {
                final elderlyName = _linked
                    .firstWhere((le) => le.elderlyId == elderlyId)
                    .name;
                String location = 'Unknown location'.tr();
                String? mapUrl;
                try {
                  final loc = jsonDecode(newLog['location'] as String);
                  location = loc['address'] ?? '${loc['lat']}, ${loc['lng']}';
                  if (loc['lat'] != null && loc['lng'] != null) {
                    mapUrl =
                        'https://maps.google.com/?q=${loc['lat']},${loc['lng']}';
                  }
                } catch (_) {}

                if (mounted) {
                  final alertId = newLog['alert_id'] as String;
                  setState(
                    () => _activeSosAlert = {
                      ...newLog,
                      'name': elderlyName,
                      'parsed_location': location,
                    },
                  );
                  SosNotificationService().showSosOverlay(
                    context: context,
                    elderlyName: elderlyName,
                    location: location,
                    mapUrl: mapUrl,
                    alertId: alertId,
                    onConfirm: _respondToSos,
                  );
                  SosNotificationService().startRepeatNotification(
                    elderlyName: elderlyName,
                    location: location,
                    alertId: alertId,
                  );
                }
                return; // Don't call _checkActiveSos again
              }
            }

            // ── Handle health missed alert ────────────────────────────────────
            if (newLog['status'] == 'health_missed' &&
                payload.eventType == PostgresChangeEvent.insert) {
              final linkId = newLog['link_id'];
              if (linkId != null) {
                final linkRow = await db
                    .from('care_link')
                    .select('elderly_id')
                    .eq('link_id', linkId)
                    .maybeSingle();
                if (linkRow != null) {
                  final eid = linkRow['elderly_id'];
                  if (_linked.any((le) => le.elderlyId == eid)) {
                    final elderlyName = _linked
                        .firstWhere((le) => le.elderlyId == eid)
                        .name;
                    SosNotificationService().showCaregiverAlert(
                      elderlyName: elderlyName,
                      title: '$elderlyName Missed Health Data',
                      message: 'Health record was not logged today.'.tr(),
                      type: CaregiverAlertType.healthMissed,
                    );
                  }
                }
              }
            } else if (newLog['status'] != null &&
                payload.eventType == PostgresChangeEvent.insert) {
              final status = newLog['status'] as String;
              if (status.startsWith('Low Stock:') ||
                  status.startsWith('Expired Medicine:') ||
                  status.startsWith('Expiring Soon:')) {
                final linkId = newLog['link_id'];
                if (linkId != null) {
                  final linkRow = await db
                      .from('care_link')
                      .select('elderly_id')
                      .eq('link_id', linkId)
                      .maybeSingle();
                  if (linkRow != null) {
                    final eid = linkRow['elderly_id'];
                    if (_linked.any((le) => le.elderlyId == eid)) {
                      final elderlyName = _linked
                          .firstWhere((le) => le.elderlyId == eid)
                          .name;
                      SosNotificationService().showCaregiverAlert(
                        elderlyName: elderlyName,
                        title:
                            status.contains('Expired') ||
                                status.contains('Expiring')
                            ? '🚫 Medicine Alert — $elderlyName'
                            : '⚠️ Low Stock — $elderlyName',
                        message: status,
                        type:
                            status.contains('Expired') ||
                                status.contains('Expiring')
                            ? CaregiverAlertType.medicineExpired
                            : CaregiverAlertType.stockLow,
                      );
                    }
                  }
                }
              }
            }
            _checkActiveSos();
          },
        )
        .subscribe();

    // 2. Missed Medication Alerts
    _medLogChannel = db
        .channel('medication_logs_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'medication_logs',
          callback: (payload) async {
            final newLog = payload.newRecord;
            if (newLog['status'] == 'missed') {
              final medId = newLog['medication_id'];
              if (medId == null) return;

              // Fetch medication details
              final medRow = await db
                  .from('medications')
                  .select('medication_name, schedule_id')
                  .eq('medication_id', medId)
                  .maybeSingle();
              if (medRow == null) return;

              final schedRow = await db
                  .from('schedule')
                  .select('elderly_id')
                  .eq('schedule_id', medRow['schedule_id'])
                  .maybeSingle();
              if (schedRow == null) return;

              final eid = schedRow['elderly_id'];

              // Check if this elderly is linked to the caregiver
              if (_linked.any((le) => le.elderlyId == eid)) {
                final elderlyName = _linked
                    .firstWhere((le) => le.elderlyId == eid)
                    .name;

                // Show a caregiver-specific local notification
                SosNotificationService().showCaregiverAlert(
                  elderlyName: elderlyName,
                  message: '${medRow['medication_name']} was not taken today.'
                      .tr(),
                  type: CaregiverAlertType.medicationMissed,
                );
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _respondToSos() async {
    if (_activeSosAlert == null) return;
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      await db
          .from('emergency_logs')
          .update({
            'status': 'resolved',
            'caregiver_id': uid,
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('alert_id', _activeSosAlert!['alert_id']);
      // Dismiss all notifications and overlay
      await SosNotificationService().dismissSosNotification();
      if (mounted) setState(() => _activeSosAlert = null);
    } catch (e) {
      debugPrint('Respond to SOS error: $e');
    }
  }

  // ─── Pages ────────────────────────────────────────────────────────────────
  Widget _buildPage() {
    switch (_navIndex) {
      case 0:
        return _PatientsPage(
          linked: _linked,
          loading: _loading,
          onRefresh: _loadAll,
          onScanTap: _openScanner,
        );
      case 1:
        return _MedMonitorPage(linked: _linked, loading: _loading);
      case 2:
        return _ScheduleMonitorPage(linked: _linked, loading: _loading);
      case 3:
        return _SettingsPage(caregiverName: _caregiverName ?? '');
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _openScanner() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CaregiverScanQrScreen()),
    );
    if (result == true) _loadAll();
  }

  int get _alertCount => _linked.where((e) => e.latestRisk == 'high').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          _buildPage(),
          // SOS Emergency Alert Banner
          if (_activeSosAlert != null) _buildSosBanner(),
        ],
      ),
      bottomNavigationBar: _buildNavBar(),
      floatingActionButton: _navIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _openScanner,
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                'Link Patient'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  Widget _buildSosBanner() {
    final alert = _activeSosAlert!;
    final name = alert['name'] ?? 'Patient'.tr();
    final location =
        alert['parsed_location'] as String? ?? 'Unknown location'.tr();
    final time = alert['timestamp'] != null
        ? DateFormat('h:mm a').format(
            DateTime.parse(
              alert['timestamp'].toString() +
                  (alert['timestamp'].toString().endsWith('Z') ? '' : 'Z'),
            ).toLocal(),
          )
        : '';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: GestureDetector(
          onTap: () => _respondToSos(),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFB71C1C),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🚨  SOS EMERGENCY ALERT'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$name needs help!'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _respondToSos,
                    icon: const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFFB71C1C),
                      size: 18,
                    ),
                    label: Text(
                      'I am Responding — Mark as Resolved'.tr(),
                      style: const TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
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

  Widget _buildNavBar() {
    final items = [
      (
        icon: Icons.people_outline,
        activeIcon: Icons.people,
        label: 'Patients'.tr(),
      ),
      (
        icon: Icons.medication_outlined,
        activeIcon: Icons.medication,
        label: 'Medication'.tr(),
      ),
      (
        icon: Icons.calendar_today_outlined,
        activeIcon: Icons.calendar_today,
        label: 'Schedule'.tr(),
      ),
      (
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Settings'.tr(),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(items.length, (i) {
            final item = items[i];
            final sel = i == _navIndex;
            final showBadge = i == 0 && _alertCount > 0;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _navIndex = i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: sel ? _kBlue : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            sel ? item.activeIcon : item.icon,
                            color: sel ? _kBlue : Colors.grey.shade400,
                            size: 24,
                          ),
                          if (showBadge)
                            Positioned(
                              right: -6,
                              top: -4,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD32F2F),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$_alertCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                          color: sel ? _kBlue : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 1 – Patients List
// ═════════════════════════════════════════════════════════════════════════════
class _PatientsPage extends StatelessWidget {
  final List<LinkedElderly> linked;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onScanTap;

  const _PatientsPage({
    required this.linked,
    required this.loading,
    required this.onRefresh,
    required this.onScanTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          if (loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _kBlue)),
            )
          else if (linked.isEmpty)
            SliverFillRemaining(child: _EmptyLinked(onScan: onScanTap))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _PatientCard(elderly: linked[i]),
                  childCount: linked.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    final highRisk = linked.where((e) => e.latestRisk == 'high').length;
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _kBlue,
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF00539E), Color(0xFF003875)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Caregiver Hub'.tr(),
                            style: TextStyle(
                              fontFamily: 'League Spartan',
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${linked.length} patient${linked.length != 1 ? 's' : ''} linked',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (highRisk > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFD32F2F,
                            ).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$highRisk HIGH RISK',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
      ],
    );
  }
}

class _PatientCard extends StatelessWidget {
  final LinkedElderly elderly;
  const _PatientCard({required this.elderly});

  @override
  Widget build(BuildContext context) {
    final rc = _riskColor(elderly.latestRisk);
    final rb = _riskBg(elderly.latestRisk);
    final rl = _riskLabel(elderly.latestRisk);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CaregiverElderlyDetailScreen(elderly: elderly),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: rc.withValues(alpha: 0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _kBlue.withValues(alpha: 0.12),
                  child: Text(
                    elderly.name.isNotEmpty
                        ? elderly.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _kBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        elderly.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _kDark,
                        ),
                      ),
                      if (elderly.chronicCondition != null &&
                          elderly.chronicCondition!.isNotEmpty)
                        Text(
                          elderly.chronicCondition!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: rb,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: rc.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    rl,
                    style: TextStyle(
                      color: rc,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Vital pills
            const SizedBox(height: 14),
            Row(
              children: [
                _vitalPill(
                  Icons.show_chart,
                  elderly.latestBP ?? '–',
                  'mmHg',
                  Colors.blue.shade600,
                ),
                const SizedBox(width: 8),
                _vitalPill(
                  Icons.favorite_border,
                  elderly.latestHR != null ? '${elderly.latestHR}' : '–',
                  'bpm',
                  Colors.red.shade400,
                ),
                const SizedBox(width: 8),
                _vitalPill(
                  Icons.thermostat,
                  elderly.latestTemp?.toStringAsFixed(1) ?? '–',
                  '°C',
                  Colors.orange.shade600,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'View full details →'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _kBlue.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _vitalPill(IconData icon, String val, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$val $unit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLinked extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyLinked({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline, size: 52, color: _kBlue),
            ),
            const SizedBox(height: 24),
            Text(
              'No patients linked yet'.tr(),
              style: TextStyle(
                fontFamily: 'League Spartan',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _kDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Scan an elderly patient\'s QR code to start monitoring their health data remotely.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _kGrey, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: Text(
                'Scan QR Code'.tr(),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 2 – Medication Monitor
// ═════════════════════════════════════════════════════════════════════════════
class _MedMonitorPage extends StatefulWidget {
  final List<LinkedElderly> linked;
  final bool loading;
  const _MedMonitorPage({required this.linked, required this.loading});

  @override
  State<_MedMonitorPage> createState() => _MedMonitorPageState();
}

class _MedMonitorPageState extends State<_MedMonitorPage> {
  // elderlyId -> list of medication maps
  Map<String, List<Map<String, dynamic>>> _medsByElderly = {};
  // elderlyId -> list of today's log maps
  Map<String, List<Map<String, dynamic>>> _logsByElderly = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_MedMonitorPage old) {
    super.didUpdateWidget(old);
    if (old.linked != widget.linked) _load();
  }

  Future<void> _load() async {
    if (widget.linked.isEmpty) return;
    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final Map<String, List<Map<String, dynamic>>> medsMap = {};
      final Map<String, List<Map<String, dynamic>>> logsMap = {};

      for (final el in widget.linked) {
        // Get schedule IDs for this elderly
        final schedRes = await db
            .from('schedule')
            .select('schedule_id')
            .eq('elderly_id', el.elderlyId);
        final schedIds = (schedRes as List)
            .map((s) => s['schedule_id'] as String)
            .toList();

        List<Map<String, dynamic>> meds = [];
        List<Map<String, dynamic>> logs = [];

        if (schedIds.isNotEmpty) {
          final medRes = await db
              .from('medications')
              .select()
              .inFilter('schedule_id', schedIds);
          meds = (medRes as List).cast<Map<String, dynamic>>();

          if (meds.isNotEmpty) {
            final medIds = meds
                .map((m) => m['medication_id'] as String)
                .toList();
            final today = DateTime.now();
            final start = DateTime(
              today.year,
              today.month,
              today.day,
            ).toUtc().toIso8601String();
            final end = DateTime(
              today.year,
              today.month,
              today.day + 1,
            ).toUtc().toIso8601String();
            final logRes = await db
                .from('medication_logs')
                .select()
                .inFilter('medication_id', medIds)
                .gte('logged_at', start)
                .lt('logged_at', end);
            logs = (logRes as List).cast<Map<String, dynamic>>();
          }
        }

        medsMap[el.elderlyId] = meds;
        logsMap[el.elderlyId] = logs;
      }

      if (mounted) {
        setState(() {
          _medsByElderly = medsMap;
          _logsByElderly = logsMap;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('MedMonitorPage load error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Med Monitor Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          _sliverHeader(
            'Medication Monitor',
            Icons.medication,
            'Today\'s medications for all patients',
            _kBlue,
          ),
          if (widget.loading || _loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _kBlue)),
            )
          else if (widget.linked.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: _NoPatientHint(
                  msg: 'Link patients to see their medications',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final el = widget.linked[i];
                  final meds = _medsByElderly[el.elderlyId] ?? [];
                  final logs = _logsByElderly[el.elderlyId] ?? [];
                  return _ElderlyMedSection(
                    elderly: el,
                    medications: meds,
                    todayLogs: logs,
                  );
                }, childCount: widget.linked.length),
              ),
            ),
        ],
      ),
    );
  }
}

class _ElderlyMedSection extends StatelessWidget {
  final LinkedElderly elderly;
  final List<Map<String, dynamic>> medications;
  final List<Map<String, dynamic>> todayLogs;

  const _ElderlyMedSection({
    required this.elderly,
    required this.medications,
    required this.todayLogs,
  });

  // ── session ordering ──────────────────────────────────────────────────────
  static const _sessionOrder = [
    'Morning',
    'Afternoon',
    'Evening',
    'Night',
    'As needed',
  ];

  static const _sessionIcons = {
    'Morning': Icons.wb_sunny_outlined,
    'Afternoon': Icons.wb_cloudy_outlined,
    'Evening': Icons.nights_stay_outlined,
    'Night': Icons.bedtime_outlined,
    'As needed': Icons.access_time,
  };

  static const _sessionColors = {
    'Morning': Color(0xFFF57C00),
    'Afternoon': Color(0xFF0288D1),
    'Evening': Color(0xFF7B1FA2),
    'Night': Color(0xFF37474F),
    'As needed': Color(0xFF00796B),
  };

  String _sessionKey(String? val) {
    if (val == null || val.isEmpty) return 'As needed';
    if (val == 'Morning') return 'Morning';
    if (val == 'Afternoon') return 'Afternoon';
    if (val == 'Evening') return 'Evening';
    if (val == 'Night') return 'Night';
    // Time strings → classify by hour
    if (val.contains(':')) {
      try {
        final h = int.parse(val.split(':')[0]);
        if (h >= 5 && h < 12) return 'Morning';
        if (h >= 12 && h < 17) return 'Afternoon';
        if (h >= 17 && h < 21) return 'Evening';
        return 'Night';
      } catch (_) {}
    }
    return 'As needed';
  }

  @override
  Widget build(BuildContext context) {
    final takenIds = todayLogs
        .where((l) => l['status'] == 'taken')
        .map((l) => l['medication_id'] as String)
        .toSet();
    final taken = medications
        .where((m) => takenIds.contains(m['medication_id']))
        .length;

    // Group by session
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final med in medications) {
      final key = _sessionKey(med['when_to_take'] as String?);
      grouped.putIfAbsent(key, () => []).add(med);
    }
    // Build in defined order, skip empty sessions
    final sessions = _sessionOrder
        .where((s) => grouped.containsKey(s))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Elderly header
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _kBlue.withValues(alpha: 0.1),
              child: Text(
                elderly.name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kBlue,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                elderly.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$taken / ${medications.length} taken',
                style: const TextStyle(
                  color: _kGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (medications.isEmpty)
          _infoCard('No medications registered')
        else
          ...sessions.map((session) {
            final meds = grouped[session]!;
            final color = _sessionColors[session] ?? _kBlue;
            final icon = _sessionIcons[session] ?? Icons.access_time;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Session header
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 16, color: color),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        session,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: color,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Divider(
                          color: color.withValues(alpha: 0.25),
                          thickness: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                // Med cards in this session
                ...meds.map((med) {
                  final medId = med['medication_id'] as String;
                  final isTaken = takenIds.contains(medId);
                  final missedLog = todayLogs.any(
                    (l) =>
                        l['medication_id'] == medId && l['status'] == 'missed',
                  );
                  final name = med['medication_name'] as String? ?? 'Unknown';
                  final dosage = med['dosage'] as String? ?? '';
                  final when = _formatWhen(med['when_to_take'] as String?);
                  final stock = med['medication_stock'] as int?;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isTaken
                            ? _kGreen.withValues(alpha: 0.3)
                            : (missedLog
                                  ? Colors.red.withValues(alpha: 0.3)
                                  : Colors.grey.shade200),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isTaken
                                ? _kGreen.withValues(alpha: 0.12)
                                : color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.medication,
                            color: isTaken ? _kGreen : color,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _kDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dosage.isNotEmpty ? '$dosage · $when' : when,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              if (stock != null)
                                Text(
                                  'Stock: $stock',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: stock <= 3
                                        ? Colors.red
                                        : Colors.grey.shade400,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _StatusBadge(taken: isTaken, missed: missedLog),
                      ],
                    ),
                  );
                }),
              ],
            );
          }),
        const Divider(height: 8),
      ],
    );
  }

  Widget _infoCard(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey.shade400, size: 18),
          const SizedBox(width: 8),
          Text(
            msg,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _formatWhen(String? val) {
    if (val == null || val.isEmpty) return 'As needed';
    if (val.contains(':')) {
      try {
        final p = val.split(':');
        final h = int.parse(p[0]);
        final m = int.parse(p[1]);
        final ampm = h >= 12 ? 'PM' : 'AM';
        final fh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
        return '$fh:${m.toString().padLeft(2, '0')} $ampm';
      } catch (_) {}
    }
    return val;
  }
}

class _StatusBadge extends StatelessWidget {
  final bool taken;
  final bool missed;
  const _StatusBadge({required this.taken, required this.missed});

  @override
  Widget build(BuildContext context) {
    if (taken) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _kGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: _kGreen, size: 14),
            SizedBox(width: 4),
            Text(
              'Taken'.tr(),
              style: TextStyle(
                color: _kGreen,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    if (missed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red, size: 14),
            SizedBox(width: 4),
            Text(
              'Missed'.tr(),
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pending_outlined, color: Colors.orange, size: 14),
          SizedBox(width: 4),
          Text(
            'Pending'.tr(),
            style: TextStyle(
              color: Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 3 – Schedule Monitor
// ═════════════════════════════════════════════════════════════════════════════
class _ScheduleMonitorPage extends StatefulWidget {
  final List<LinkedElderly> linked;
  final bool loading;
  const _ScheduleMonitorPage({required this.linked, required this.loading});

  @override
  State<_ScheduleMonitorPage> createState() => _ScheduleMonitorPageState();
}

class _ScheduleMonitorPageState extends State<_ScheduleMonitorPage> {
  Map<String, List<Map<String, dynamic>>> _schedulesByElderly = {};
  bool _loading = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ScheduleMonitorPage old) {
    super.didUpdateWidget(old);
    if (old.linked != widget.linked) _load();
  }

  Future<void> _load() async {
    if (widget.linked.isEmpty) return;
    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final Map<String, List<Map<String, dynamic>>> result = {};

      // Fetch 7-day window around selected date
      final start = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day - 3,
      ).toUtc().toIso8601String();
      final end = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + 4,
      ).toUtc().toIso8601String();

      for (final el in widget.linked) {
        final res = await db
            .from('schedule')
            .select()
            .eq('elderly_id', el.elderlyId)
            .gte('schedule_date_time', start)
            .lte('schedule_date_time', end)
            .order('schedule_date_time', ascending: true);
        result[el.elderlyId] = (res as List).cast<Map<String, dynamic>>();
      }

      if (mounted) {
        setState(() {
          _schedulesByElderly = result;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ScheduleMonitorPage load error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schedule Monitor Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          _sliverHeader(
            'Schedule Monitor',
            Icons.calendar_today,
            DateFormat('EEEE, d MMMM').format(_selectedDate),
            _kBlue,
          ),
          // Date strip
          SliverToBoxAdapter(child: _buildDateStrip()),
          if (widget.loading || _loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _kBlue)),
            )
          else if (widget.linked.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: _NoPatientHint(
                  msg: 'Link patients to see their schedule',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final el = widget.linked[i];
                  final items = _schedulesByElderly[el.elderlyId] ?? [];
                  // Filter to selected date and exclude Medication-type entries
                  final todayItems = items.where((s) {
                    final raw = s['schedule_date_time'] as String;
                    final dt = raw.endsWith('Z')
                        ? DateTime.parse(raw).toLocal()
                        : DateTime.parse('${raw}Z').toLocal();
                    if (!(dt.year == _selectedDate.year &&
                        dt.month == _selectedDate.month &&
                        dt.day == _selectedDate.day)) {
                      return false;
                    }
                    // Exclude medication schedule entries
                    try {
                      final notes = s['notes'] as String? ?? '';
                      const marker = '\n\n__METADATA__:';
                      if (notes.contains(marker)) {
                        final parts = notes.split(marker);
                        if (parts.length > 1) {
                          final meta =
                              jsonDecode(parts.sublist(1).join(marker))
                                  as Map<String, dynamic>;
                          if ((meta['type'] as String?) == 'Medication') {
                            return false;
                          }
                        }
                      }
                    } catch (_) {}
                    return true;
                  }).toList();
                  return _ElderlyScheduleSection(
                    elderly: el,
                    schedules: todayItems,
                  );
                }, childCount: widget.linked.length),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateStrip() {
    final days = List.generate(
      7,
      (i) => DateTime.now().add(Duration(days: i - 3)),
    );
    return Container(
      height: 80,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final d = days[i];
          final sel =
              d.year == _selectedDate.year &&
              d.month == _selectedDate.month &&
              d.day == _selectedDate.day;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedDate = d);
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: sel ? _kBlue : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? _kBlue : Colors.grey.shade200),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E').format(d),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: sel
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: sel ? Colors.white : _kDark,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ElderlyScheduleSection extends StatelessWidget {
  final LinkedElderly elderly;
  final List<Map<String, dynamic>> schedules;

  const _ElderlyScheduleSection({
    required this.elderly,
    required this.schedules,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _kBlue.withValues(alpha: 0.1),
              child: Text(
                elderly.name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kBlue,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                elderly.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
                ),
              ),
            ),
            Text(
              '${schedules.length} event${schedules.length != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (schedules.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_available,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'No events today'.tr(),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...schedules.map((s) => _buildScheduleCard(s)),
        const Divider(height: 8),
      ],
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> s) {
    final raw = s['schedule_date_time'] as String;
    final dt = raw.endsWith('Z')
        ? DateTime.parse(raw).toLocal()
        : DateTime.parse('${raw}Z').toLocal();
    final title = s['title'] as String? ?? 'Untitled';
    final location = s['location'] as String?;
    final notes = s['notes'] as String? ?? '';

    // Parse metadata from notes
    String type = 'Appointment';
    String status = 'pending';
    String priority = 'medium';
    try {
      final marker = '\n\n__METADATA__:';
      if (notes.contains(marker)) {
        final parts = notes.split(marker);
        if (parts.length > 1) {
          final meta =
              jsonDecode(parts.sublist(1).join(marker)) as Map<String, dynamic>;
          type = meta['type'] as String? ?? 'Appointment';
          status = meta['status'] as String? ?? 'pending';
          priority = meta['priority'] as String? ?? 'medium';
        }
      }
    } catch (_) {}

    Color typeColor;
    switch (type) {
      case 'Medication':
        typeColor = _kBlue;
        break;
      case 'Personal':
        typeColor = _kGreen;
        break;
      default:
        typeColor = const Color(0xFF7B1FA2);
    }

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'done':
        statusColor = _kGreen;
        statusIcon = Icons.check_circle;
        break;
      case 'skip':
        statusColor = Colors.grey;
        statusIcon = Icons.skip_next;
        break;
      case 'missed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          // Time column
          SizedBox(
            width: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('h:mm').format(dt),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _kDark,
                  ),
                ),
                Text(
                  DateFormat('a').format(dt),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 50,
            color: Colors.grey.shade200,
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _kDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (location != null && location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          location,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Status
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 4 – Settings
// ═════════════════════════════════════════════════════════════════════════════
class _SettingsPage extends StatefulWidget {
  final String caregiverName;
  const _SettingsPage({required this.caregiverName});

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool _notificationsEnabled = true;

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.tr()),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          _sliverHeader(
            'Settings',
            Icons.settings,
            widget.caregiverName,
            _kBlue,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _settingTile(
                  Icons.person_outline,
                  'Profile',
                  'Manage your caregiver profile',
                  () => _openAccountInfo(),
                ),
                _settingTile(
                  Icons.notifications_outlined,
                  'Notifications',
                  'Configure alert preferences',
                  () => _openNotifications(),
                ),
                _settingTile(
                  Icons.privacy_tip_outlined,
                  'Privacy',
                  'Data usage and permissions',
                  () => _openPrivacy(),
                ),
                const SizedBox(height: 20),
                _logoutButton(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingTile(
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: _kBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _kBlue, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          sub,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
        onTap: onTap,
      ),
    );
  }

  Widget _logoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () async {
          await Supabase.instance.client.auth.signOut();
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (r) => false,
            );
          }
        },
        icon: const Icon(Icons.logout, color: Colors.red, size: 20),
        label: Text(
          'Sign Out'.tr(),
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ─── Settings Methods ────────────────────────────────────────────────────────

  void _openAccountInfo() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final res = await Supabase.instance.client
        .from('users')
        .select('fullname, phone_num, address')
        .eq('user_id', uid)
        .maybeSingle();

    if (!mounted) return;

    final nameCtrl = TextEditingController(text: res?['fullname'] ?? '');
    final phoneCtrl = TextEditingController(text: res?['phone_num'] ?? '');
    final addressCtrl = TextEditingController(text: res?['address'] ?? '');

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) {
          return _buildBottomSheet(
            title: 'Account Info'.tr(),
            icon: Icons.person_outline_rounded,
            child: Column(
              children: [
                _inputField('Full Name', nameCtrl, Icons.person_outline),
                const SizedBox(height: 12),
                _inputField('Phone Number', phoneCtrl, Icons.phone_outlined),
                const SizedBox(height: 12),
                LocationSearchField(
                  controller: addressCtrl,
                  label: 'Address',
                  hint: 'Enter your address',
                  prefixIcon: Icons.home_outlined,
                  themeColor: _kBlue,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await Supabase.instance.client
                            .from('users')
                            .update({
                              'fullname': nameCtrl.text.trim(),
                              'phone_num': phoneCtrl.text.trim(),
                              'address': addressCtrl.text.trim(),
                            })
                            .eq('user_id', uid);
                        if (mounted) {
                          Navigator.pop(ctx);
                          _snack('Profile updated successfully!');
                        }
                      } catch (e) {
                        _snack('Error: $e', isError: true);
                      }
                    },
                    child: Text(
                      'Save Changes'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openNotifications() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) {
          return _buildBottomSheet(
            title: 'Notifications'.tr(),
            icon: Icons.notifications_none_rounded,
            child: Column(
              children: [
                _settingSwitch(
                  Icons.notifications_active_outlined,
                  'Push Notifications',
                  'Receive alerts on your device',
                  _notificationsEnabled,
                  (v) {
                    setBS(() => _notificationsEnabled = v);
                    setState(() => _notificationsEnabled = v);
                  },
                ),
                const SizedBox(height: 12),
                _settingSwitch(
                  Icons.health_and_safety_outlined,
                  'SOS Alerts',
                  'Emergency alerts from patients',
                  true,
                  (_) {},
                ),
                const SizedBox(height: 12),
                _settingSwitch(
                  Icons.medication_outlined,
                  'Missed Medication',
                  'Alert when patient misses medicine',
                  true,
                  (_) {},
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openPrivacy() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildBottomSheet(
        title: 'Privacy'.tr(),
        icon: Icons.privacy_tip_outlined,
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, color: _kBlue),
              title: const Text(
                'Terms of Service',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(
                Icons.open_in_new,
                size: 16,
                color: Colors.grey,
              ),
              onTap: () {},
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.policy_outlined, color: _kBlue),
              title: const Text(
                'Privacy Policy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(
                Icons.open_in_new,
                size: 16,
                color: Colors.grey,
              ),
              onTap: () {},
            ),
            const SizedBox(height: 12),
            const Text(
              'Your data is securely stored and only accessible by you and authorized caregivers.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(icon, color: _kBlue, size: 28),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _inputField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    int lines = 1,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label.tr(),
        prefixIcon: Icon(icon, color: Colors.grey),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _settingSwitch(
    IconData icon,
    String title,
    String sub,
    bool val,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _kBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.tr(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  sub.tr(),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Switch(value: val, activeThumbColor: _kBlue, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ─── Shared helpers ──────────────────────────────────────────────────────────
SliverAppBar _sliverHeader(
  String title,
  IconData icon,
  String subtitle,
  Color color,
) {
  return SliverAppBar(
    pinned: true,
    backgroundColor: color,
    foregroundColor: Colors.white,
    automaticallyImplyLeading: false,
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'League Spartan',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    expandedHeight: 90,
  );
}

class _NoPatientHint extends StatelessWidget {
  final String msg;
  const _NoPatientHint({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
