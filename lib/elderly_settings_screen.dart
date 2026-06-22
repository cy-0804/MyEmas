import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'login_screen.dart';

const _kBlue = Color(0xFF00539E);
const _kBg = Color(0xFFF6F8FA);
const _kTextDark = Color(0xFF1A1D2E);

class ElderlySettingsScreen extends StatefulWidget {
  const ElderlySettingsScreen({super.key});

  @override
  State<ElderlySettingsScreen> createState() => _ElderlySettingsScreenState();
}

class _ElderlySettingsScreenState extends State<ElderlySettingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _userName = '';
  String _userEmail = '';
  bool _notificationsEnabled = true;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final res = await Supabase.instance.client
          .from('users')
          .select('fullname, email')
          .eq('user_id', uid)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _userName = res?['fullname'] as String? ?? '';
          _userEmail = res?['email'] as String? ??
              Supabase.instance.client.auth.currentUser?.email ?? '';
        });
      }
    } catch (_) {}
  }

  List<_SettingItem> get _visibleItems {
    final items = [
      _SettingItem(
        icon: Icons.person_outline_rounded,
        title: 'Account Info',
        subtitle: 'Edit your personal info',
        keywords: const ['name', 'phone', 'address', 'gender', 'profile', 'personal'],
        onTap: _openAccountInfo,
      ),
      _SettingItem(
        icon: Icons.lock_outline_rounded,
        title: 'Security & Data',
        subtitle: 'Manage personal info',
        keywords: const ['password', 'biometric', 'fingerprint', 'delete account', 'security', 'login'],
        onTap: _openSecurity,
      ),
      _SettingItem(
        icon: Icons.tune_rounded,
        title: 'Preference',
        subtitle: 'App theme, language and accessibility settings',
        keywords: const ['language', 'font size', 'text size', 'theme', 'accessibility', 'english', 'bahasa', 'melayu'],
        onTap: _openPreference,
      ),
      _SettingItem(
        icon: Icons.notifications_none_rounded,
        title: 'Notifications',
        subtitle: 'Notifications and reminder settings',
        keywords: const ['push', 'medication', 'schedule', 'reminder', 'alert', 'health', 'sound'],
        onTap: _openNotifications,
      ),
      _SettingItem(
        icon: Icons.medical_services_outlined,
        title: 'Caregivers',
        subtitle: 'Add or remove caregivers',
        keywords: const ['caregiver', 'unlink', 'remove', 'primary', 'contact'],
        onTap: _manageCaregivers,
      ),
      _SettingItem(
        icon: Icons.qr_code_2_rounded,
        title: 'My QR Code',
        subtitle: 'Share with your caregiver to link',
        keywords: const ['qr code', 'share', 'link', 'scan'],
        onTap: _showQrCode,
      ),
      _SettingItem(
        icon: Icons.logout_rounded,
        title: 'Log out',
        subtitle: 'Log out from your account',
        keywords: const ['log out', 'logout', 'sign out', 'exit'],
        onTap: _confirmLogout,
        isDestructive: true,
      ),
    ];

    if (_searchQuery.isEmpty) return items;
    return items.where((i) {
      final q = _searchQuery.toLowerCase();
      if (i.title.toLowerCase().contains(q)) return true;
      if (i.subtitle.toLowerCase().contains(q)) return true;
      if (i.keywords.any((k) => k.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  // ─── Account Info ──────────────────────────────────────────────────────────
  void _openAccountInfo() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final res = await Supabase.instance.client
        .from('users')
        .select('fullname, gender, date_of_birth, address, phone_num, icno')
        .eq('user_id', uid)
        .maybeSingle();

    if (!mounted) return;

    final nameCtrl = TextEditingController(text: res?['fullname'] ?? '');
    final phoneCtrl = TextEditingController(text: res?['phone_num'] ?? '');
    final addressCtrl = TextEditingController(text: res?['address'] ?? '');
    
    // Sanitize gender to exactly 'Male' or 'Female' to prevent Dropdown crash
    String? rawGender = res?['gender']?.toString().toLowerCase();
    String? gender;
    if (rawGender == 'male') gender = 'Male';
    if (rawGender == 'female') gender = 'Female';

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) {
        return _buildBottomSheet(
          ctx,
          title: 'Account Info',
          icon: Icons.person_outline_rounded,
          child: Column(children: [
            _inputField('Full Name', nameCtrl, Icons.person_outline),
            const SizedBox(height: 12),
            _inputField('Phone Number', phoneCtrl, Icons.phone_outlined),
            const SizedBox(height: 12),
            _inputField('Address', addressCtrl, Icons.home_outlined, lines: 2),
            const SizedBox(height: 12),
            // Gender picker
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(Icons.wc_outlined, color: Colors.grey.shade500, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: gender,
                      hint: Text('Gender', style: TextStyle(color: Colors.grey.shade400)),
                      isExpanded: true,
                      items: ['Male', 'Female']
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) => setBS(() => gender = v),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            _saveButton(() async {
              try {
                await Supabase.instance.client.from('users').update({
                  'fullname': nameCtrl.text.trim(),
                  'phone_num': phoneCtrl.text.trim(),
                  'address': addressCtrl.text.trim(),
                  if (gender != null) 'gender': gender,
                }).eq('user_id', uid);
                _loadUserData();
                if (mounted) Navigator.pop(ctx);
                _snack('Profile updated successfully!');
              } catch (e) {
                _snack('Error: $e', isError: true);
              }
            }),
          ]),
        );
      }),
    );
  }

  // ─── Security & Data ───────────────────────────────────────────────────────
  void _openSecurity() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildBottomSheet(
        ctx,
        title: 'Security & Data',
        icon: Icons.lock_outline_rounded,
        child: Column(children: [
          _tileRow(Icons.lock_reset_outlined, 'Change Password', 'Update your account password',
            onTap: () => _changePassword(ctx)),
          const SizedBox(height: 12),
          _tileRow(Icons.fingerprint_rounded, 'Biometric Login', 'Use fingerprint to sign in',
            trailing: Switch(
              value: _biometricEnabled,
              activeColor: _kBlue,
              onChanged: (v) {
                setState(() => _biometricEnabled = v);
                Navigator.pop(ctx);
                _snack(v ? 'Biometric login enabled' : 'Biometric login disabled');
              },
            )),
          const SizedBox(height: 12),
          _tileRow(Icons.delete_outline_rounded, 'Delete Account', 'Permanently remove your account',
            isDestructive: true,
            onTap: () {
              Navigator.pop(ctx);
              _confirmDeleteAccount();
            }),
        ]),
      ),
    );
  }

  void _changePassword(BuildContext ctx) {
    Navigator.pop(ctx);
    final emailCtrl = TextEditingController(text: _userEmail);
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('We will send a password reset link to your email.'),
          const SizedBox(height: 16),
          TextField(
            controller: emailCtrl,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kBlue, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(emailCtrl.text.trim());
                if (mounted) Navigator.pop(dctx);
                _snack('Reset link sent to ${emailCtrl.text}');
              } catch (e) {
                _snack('Error: $e', isError: true);
              }
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text('This action is permanent and cannot be undone. All your data will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── Preference ────────────────────────────────────────────────────────────
  void _openPreference() {
    String selectedLang = 'English';
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) {
        return _buildBottomSheet(
          ctx,
          title: 'Preference',
          icon: Icons.tune_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Language', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 8),
            ...['English', 'Bahasa Melayu', '中文'].map((lang) => RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: Text(lang),
              value: lang,
              groupValue: selectedLang,
              activeColor: _kBlue,
              onChanged: (v) => setBS(() => selectedLang = v!),
            )),
            const SizedBox(height: 12),
            Text('Font Size', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 8),
            _tileRow(Icons.text_fields_rounded, 'Large Text', 'Increase text size for readability',
              trailing: Switch(value: false, activeColor: _kBlue, onChanged: (_) {})),
            const SizedBox(height: 24),
            _saveButton(() {
              Navigator.pop(ctx);
              _snack('Preferences saved!');
            }),
          ]),
        );
      }),
    );
  }

  // ─── Notifications ─────────────────────────────────────────────────────────
  void _openNotifications() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) {
        return _buildBottomSheet(
          ctx,
          title: 'Notifications',
          icon: Icons.notifications_none_rounded,
          child: Column(children: [
            _tileRow(Icons.notifications_active_outlined, 'Push Notifications', 'Receive alerts on your device',
              trailing: Switch(
                value: _notificationsEnabled,
                activeColor: _kBlue,
                onChanged: (v) {
                  setBS(() => _notificationsEnabled = v);
                  setState(() => _notificationsEnabled = v);
                },
              )),
            const SizedBox(height: 12),
            _tileRow(Icons.medication_outlined, 'Medication Reminders', 'Get reminded to take your medicine',
              trailing: Switch(value: true, activeColor: _kBlue, onChanged: (_) {})),
            const SizedBox(height: 12),
            _tileRow(Icons.calendar_today_outlined, 'Schedule Reminders', 'Appointment and schedule alerts',
              trailing: Switch(value: true, activeColor: _kBlue, onChanged: (_) {})),
            const SizedBox(height: 12),
            _tileRow(Icons.health_and_safety_outlined, 'Health Alerts', 'High risk health record warnings',
              trailing: Switch(value: true, activeColor: _kBlue, onChanged: (_) {})),
          ]),
        );
      }),
    );
  }

  // ─── Caregivers ────────────────────────────────────────────────────────────
  Future<void> _manageCaregivers() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: _kBlue)),
    );
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      final links = await db.from('care_link').select('caregiver_id, emergency_contact_primary').eq('elderly_id', uid!);
      if (!mounted) return;
      Navigator.pop(context);

      if ((links as List).isEmpty) {
        _snack('No caregivers linked yet. Ask your caregiver to scan your QR code.');
        return;
      }

      final cgIds = links.map((l) => l['caregiver_id']).toList();
      final usersRes = await db.from('users').select('user_id, fullname, phone_num').inFilter('user_id', cgIds);
      final users = usersRes as List;

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _buildBottomSheet(
          ctx,
          title: 'My Caregivers',
          icon: Icons.medical_services_outlined,
          child: Column(children: [
            ...users.map((u) {
              final link = links.firstWhere((l) => l['caregiver_id'] == u['user_id'], orElse: () => {});
              final isPrimary = link['emergency_contact_primary'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isPrimary ? _kBlue.withValues(alpha: 0.4) : Colors.grey.shade200),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _kBlue.withValues(alpha: 0.1),
                    child: const Icon(Icons.person, color: _kBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(u['fullname'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: _kBlue, borderRadius: BorderRadius.circular(6)),
                          child: const Text('Primary', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ]),
                    if (u['phone_num'] != null)
                      Text(u['phone_num'], style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ])),
                  IconButton(
                    icon: const Icon(Icons.link_off_rounded, color: Colors.red, size: 20),
                    tooltip: 'Unlink',
                    onPressed: () async {
                      try {
                        await db.from('care_link').delete().eq('elderly_id', uid).eq('caregiver_id', u['user_id']);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Unlinked ${u['fullname']}');
                      } catch (e) {
                        _snack('Error unlinking: $e', isError: true);
                      }
                    },
                  ),
                ]),
              );
            }),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _snack('Error: $e', isError: true);
      }
    }
  }

  // ─── QR Code ───────────────────────────────────────────────────────────────
  void _showQrCode() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildBottomSheet(
        ctx,
        title: 'My QR Code',
        icon: Icons.qr_code_2_rounded,
        child: Column(children: [
          Text(
            'Share this QR code with your caregiver so they can link to your account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20)],
              ),
              child: QrImageView(data: uid, version: QrVersions.auto, size: 200, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          Text(_userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text(_userEmail, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ]),
      ),
    );
  }

  // ─── Logout ────────────────────────────────────────────────────────────────
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out from your account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              Navigator.pop(dctx);
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (r) => false,
                );
              }
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF2E7D52),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _buildBottomSheet(BuildContext ctx, {required String title, required IconData icon, required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 8,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _kBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: _kBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kTextDark)),
          ]),
          const SizedBox(height: 24),
          child,
        ]),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, IconData icon, {int lines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kBlue)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _tileRow(IconData icon, String title, String subtitle, {Widget? trailing, VoidCallback? onTap, bool isDestructive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isDestructive ? Colors.red.withValues(alpha: 0.1) : _kBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: isDestructive ? Colors.red : _kBlue),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: isDestructive ? Colors.red : _kTextDark, fontSize: 15)),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ])),
          trailing ?? (onTap != null ? Icon(Icons.chevron_right, color: Colors.grey.shade400) : const SizedBox.shrink()),
        ]),
      ),
    );
  }

  Widget _saveButton(VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: const Text(
                'Settings',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _kTextDark, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(height: 16),

            // ── Search Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
                ),
                child: Row(children: [
                  const SizedBox(width: 14),
                  Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search Settings',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {}, // Voice search hookup
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.mic_none_rounded, color: Colors.grey.shade400, size: 20),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // ── Settings Items ──
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 160),
                itemCount: items.isEmpty ? 1 : items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Column(children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No results found', style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
                        ]),
                      ),
                    );
                  }
                  final item = items[i];
                  return _buildSettingCard(item);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard(_SettingItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: item.isDestructive
                  ? Colors.red.withValues(alpha: 0.08)
                  : _kBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              color: item.isDestructive ? Colors.red : _kBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              item.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: item.isDestructive ? Colors.red : _kTextDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.3),
            ),
          ])),
          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 22),
        ]),
      ),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.keywords = const [],
    this.onTap,
    this.isDestructive = false,
  });
}
