import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'health_dashboard_view.dart';
import 'medication_dashboard_view.dart';
import 'schedule_dashboard_view.dart';
import 'add_edit_schedule_screen.dart';
import 'login_screen.dart';
import 'voice_search_helper.dart';

const _kPrimary = Color(0xFF51A77B);
const _kBlue    = Color(0xFF00539E);
const _kBg      = Color(0xFFF6F8FA);

class ElderlyDashboard extends StatefulWidget {
  const ElderlyDashboard({super.key});
  @override State<ElderlyDashboard> createState() => _ElderlyDashboardState();
}

class _ElderlyDashboardState extends State<ElderlyDashboard> {
  int _selectedIndex = 0;
  String _userName = 'User';
  List<Map<String, dynamic>> _upcomingSchedules = [];
  bool _loadingSchedules = true;
  HealthRecord? _latestRecord;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

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
          _latestRecord = healthRes != null ? HealthRecord.fromMap(healthRes) : null;
          _loadingSchedules = false;
        });
      }
    } catch (e) {
      debugPrint('Dashboard load error: $e');
      if (mounted) setState(() => _loadingSchedules = false);
    }
  }

  void _openAddHealthRecord() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditHealthRecordScreen(elderlyId: uid)));
    _loadUserData();
  }

  void _openAddMedicine() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEditMedicineScreen()));
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
                if (cmd.contains('medicine') || cmd.contains('medicat') || cmd.contains('pill')) {
                  if (cmd.contains('add')) {
                    _openAddMedicine();
                  } else {
                    setState(() => _selectedIndex = 2);
                  }
                } else if (cmd.contains('health') || cmd.contains('record') || cmd.contains('blood')) {
                  if (cmd.contains('add')) {
                    _openAddHealthRecord();
                  } else {
                    setState(() => _selectedIndex = 1);
                  }
                } else if (cmd.contains('schedule') || cmd.contains('calendar') || cmd.contains('appointment') || cmd.contains('event')) {
                  if (cmd.contains('add') || cmd.contains('new') || cmd.contains('create')) {
                    _openAddSchedule();
                  } else {
                    setState(() => _selectedIndex = 3);
                  }
                } else if (cmd.contains('home') || cmd.contains('dashboard') || cmd.contains('main')) {
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
                      _buildSettingsTab(),
                    ],
                  ),
                  // SOS Floating Button
                  Positioned(
                    right: 16,
                    bottom: 80,
                    child: _buildSosButton(),
                  ),
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
    final greeting = now.hour < 12 ? 'Good Morning' : now.hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── top bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greeting, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  RichText(text: TextSpan(children: [
                    const TextSpan(text: 'Hello, ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF27252E), fontFamily: 'League Spartan')),
                    TextSpan(text: _userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kBlue, fontFamily: 'League Spartan')),
                    const TextSpan(text: ' 👋', style: TextStyle(fontSize: 22)),
                  ])),
                ]),
                _buildNotificationIcon(),
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
                boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(DateFormat('EEEE').format(now), style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(DateFormat('d MMMM yyyy').format(now), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(DateFormat('hh:mm a').format(now), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  ]),
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.calendar_today, color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Health Summary ──
          _buildSectionHeader('Health Summary', onTap: () => setState(() => _selectedIndex = 1)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _latestRecord == null
                ? _buildHealthSummaryEmpty()
                : _buildHealthSummaryCards(),
          ),

          const SizedBox(height: 24),

          // ── Quick Actions ──
          _buildSectionHeader('Quick Actions'),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.4,
              children: [
                _buildQuickAction('Health Record', Icons.monitor_heart, const Color(0xFFE8F5E9), _kPrimary, _openAddHealthRecord),
                _buildQuickAction('Log Medicine', Icons.medication_liquid, const Color(0xFFE3F2FD), _kBlue, _openAddMedicine),
                _buildQuickAction('Schedule', Icons.calendar_month, const Color(0xFFFFF3E0), Colors.orange, () => setState(() => _selectedIndex = 3)),
                _buildQuickAction('Emergency', Icons.sos_outlined, const Color(0xFFFFEBEE), Colors.red, () {}),
              ],
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildHealthSummaryEmpty() {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 1),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: Column(children: [
          Icon(Icons.monitor_heart_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No health records yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Tap to record your health data', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
        ]),
      ),
    );
  }

  Widget _buildHealthSummaryCards() {
    final r = _latestRecord!;
    return Column(children: [
      Row(children: [
        Expanded(child: _miniHealthCard('Heart Rate', r.heartRate?.toString() ?? '–', 'bpm', Icons.favorite, Colors.red.shade300, Colors.red.shade50)),
        const SizedBox(width: 14),
        Expanded(child: _miniHealthCard('Blood Pressure', r.bloodPressure ?? '–', 'mmHg', Icons.show_chart, Colors.blue.shade400, Colors.blue.shade50)),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _miniHealthCard('Glucose', r.glucoseLevel?.toStringAsFixed(1) ?? '–', 'mmol/L', Icons.bloodtype, Colors.green.shade400, Colors.green.shade50)),
        const SizedBox(width: 14),
        Expanded(child: _miniHealthCard('Temperature', r.temperature?.toStringAsFixed(1) ?? '–', '°C', Icons.thermostat, Colors.orange.shade400, Colors.orange.shade50)),
      ]),
    ]);
  }

  Widget _miniHealthCard(String title, String value, String unit, IconData icon, Color iconColor, Color iconBg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, color: Color(0xFF6C7278), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, size: 18, color: iconColor)),
        ]),
        const SizedBox(height: 12),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF27252E))),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(unit, style: TextStyle(fontSize: 16, color: Colors.grey.shade500))),
          ])),
      ]),
    );
  }

  Widget _buildQuickAction(String title, IconData icon, Color bg, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, size: 36, color: color),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontFamily: 'League Spartan', fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF27252E))),
        if (onTap != null)
          GestureDetector(onTap: onTap, child: const Text('View All', style: TextStyle(fontSize: 16, color: _kPrimary, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _buildNotificationIcon() {
    return Stack(children: [
      const Icon(Icons.notifications_none, size: 30, color: Color(0xFF27252E)),
      Positioned(right: 3, top: 3, child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
    ]);
  }

  // ─── Settings Tab ────────────────────────────────────────────────────────────
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(children: [
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Settings', style: const TextStyle(fontFamily: 'League Spartan', fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF27252E))),
        ),
        const SizedBox(height: 24),
        // Profile section
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: Row(children: [
            CircleAvatar(radius: 30, backgroundColor: _kPrimary.withOpacity(0.15), child: Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _kPrimary))),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF27252E))),
              Text(Supabase.instance.client.auth.currentUser?.email ?? '', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        _settingsItem(Icons.person_outline, 'My Profile', _kBlue),
        _settingsItem(Icons.lock_outline, 'Change Password', _kBlue),
        _settingsItem(Icons.language, 'Language', _kBlue),
        _settingsItem(Icons.notifications_none, 'Notifications', _kBlue),
        _settingsItem(Icons.help_outline, 'Help & Support', _kBlue),
        const SizedBox(height: 12),
        _settingsItem(Icons.logout, 'Log Out', Colors.red, onTap: () async {
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (r) => false,
            );
          }
        }),
      ]),
    );
  }

  Widget _settingsItem(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: label == 'Log Out' ? Colors.red : const Color(0xFF27252E))),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  // ─── SOS Button ──────────────────────────────────────────────────────────────
  Widget _buildSosButton() {
    return GestureDetector(
      onLongPress: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🆘 SOS Alert Sent!'), backgroundColor: Colors.red));
      },
      child: Container(
        width: 70, height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.25), blurRadius: 16, spreadRadius: 4)],
        ),
        child: Center(
          child: Container(
            width: 55, height: 55,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFFF9D5C), Color(0xFFFF5252)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('SOS', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.0)),
              Text('Hold', style: TextStyle(color: Colors.white70, fontSize: 9)),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── Bottom Nav ──────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(0, Icons.home_rounded, 'HOME'),
          _navItem(1, Icons.monitor_heart_rounded, 'HEALTH'),
          _navItem(2, Icons.medication_liquid, 'MEDICINE'),
          _navItem(3, Icons.calendar_today, 'SCHEDULE'),
          _navItem(4, Icons.settings_rounded, 'SETTINGS'),
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
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: sel ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4) : EdgeInsets.zero,
          decoration: BoxDecoration(color: sel ? _kBlue.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
