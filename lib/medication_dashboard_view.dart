import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─── colour tokens (matching app design system) ───────────────────────────────
const _kPrimary  = Color(0xFF51A77B);
const _kBlue     = Color(0xFF00539E);
const _kBg       = Color(0xFFF6F8FA);
const _kCard     = Colors.white;
const _kTextDark = Color(0xFF27252E);
const _kTextGrey = Color(0xFF6C7278);

// ─── notification helper ──────────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifPlugin = FlutterLocalNotificationsPlugin();

Future<void> initMedicationNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true);
  await _notifPlugin.initialize(const InitializationSettings(android: android, iOS: ios));
}

Future<void> showMedicationReminder({required String name, required String dosage, required String instruction}) async {
  const androidDetails = AndroidNotificationDetails(
    'medication_channel', 'Medication Reminders',
    channelDescription: 'Reminds you to take your medication',
    importance: Importance.high, priority: Priority.high,
    styleInformation: BigTextStyleInformation(''),
  );
  await _notifPlugin.show(
    name.hashCode,
    '💊 Time To Take Medicine!',
    '$name — $dosage. $instruction',
    const NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails()),
  );
}

// ─── Medication model ─────────────────────────────────────────────────────────
class Medication {
  final String   id;
  final String   name;
  final String?  dosage;
  final String?  whenToTake;
  final String?  instruction;
  final int?     stock;
  final String?  notes;
  final String?  scheduleId;
  final DateTime? expirationDate;
  final String?  priority;
  final String?  photo;

  Medication({
    required this.id,
    required this.name,
    this.dosage,
    this.whenToTake,
    this.instruction,
    this.stock,
    this.notes,
    this.scheduleId,
    this.expirationDate,
    this.priority,
    this.photo,
  });

  factory Medication.fromMap(Map<String, dynamic> m) => Medication(
    id:             m['medication_id'] as String,
    name:           m['medication_name'] as String? ?? '',
    dosage:         m['dosage']      as String?,
    whenToTake:     m['when_to_take'] as String?,
    instruction:    m['instruction'] as String?,
    stock:          m['medication_stock'] as int?,
    notes:          m['medical_notes']    as String?,
    scheduleId:     m['schedule_id'] as String?,
    expirationDate: m['expiration_date'] != null ? DateTime.tryParse(m['expiration_date'] as String) : null,
    priority:       m['priority'] as String?,
    photo:          m['photo'] as String?,
  );
}

// ─── Medication Log model ─────────────────────────────────────────────────────
class MedicationLog {
  final String   id;
  final String   medicationId;
  final String   status; // 'taken' | 'missed'
  final DateTime loggedAt;
  String?        medicationName;

  MedicationLog({
    required this.id,
    required this.medicationId,
    required this.status,
    required this.loggedAt,
    this.medicationName,
  });

  factory MedicationLog.fromMap(Map<String, dynamic> m) => MedicationLog(
    id:           m['log_id']       as String,
    medicationId: m['medication_id'] as String,
    status:       m['status']       as String,
    loggedAt:     DateTime.parse(m['logged_at'] as String).toLocal(),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// MEDICATION DASHBOARD VIEW  (Tab inside ElderlyDashboard)
// ═════════════════════════════════════════════════════════════════════════════
class MedicationDashboardView extends StatefulWidget {
  const MedicationDashboardView({super.key});
  @override State<MedicationDashboardView> createState() => _MedicationDashboardViewState();
}

class _MedicationDashboardViewState extends State<MedicationDashboardView> {
  List<Medication>    _medications = [];
  List<MedicationLog> _todayLogs   = [];
  bool _loading = true;
  int  _logTab  = 1; // 0=Yesterday 1=Today 2=Tomorrow

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // Load medications via schedule (elderly's schedules → medications)
      final schedRes = await Supabase.instance.client
          .from('schedule')
          .select('schedule_id')
          .eq('elderly_id', uid);

      final scheduleIds = (schedRes as List).map((s) => s['schedule_id'] as String).toList();

      List<Medication> meds = [];
      if (scheduleIds.isNotEmpty) {
        final medRes = await Supabase.instance.client
            .from('medications')
            .select()
            .inFilter('schedule_id', scheduleIds);
        meds = (medRes as List).map((m) => Medication.fromMap(m as Map<String, dynamic>)).toList();
      }

      // Load today's logs
      final now   = DateTime.now();
      DateTime start, end;
      switch (_logTab) {
        case 0: final y = now.subtract(const Duration(days: 1)); start = DateTime(y.year, y.month, y.day); end = start.add(const Duration(days: 1)); break;
        case 2: final t = now.add(const Duration(days: 1));      start = DateTime(t.year, t.month, t.day); end = start.add(const Duration(days: 1)); break;
        default: start = DateTime(now.year, now.month, now.day); end = start.add(const Duration(days: 1)); break;
      }

      List<MedicationLog> logs = [];
      if (meds.isNotEmpty) {
        final medIds = meds.map((m) => m.id).toList();
        final logRes = await Supabase.instance.client
            .from('medication_logs')
            .select()
            .inFilter('medication_id', medIds)
            .gte('logged_at', start.toUtc().toIso8601String())
            .lt('logged_at',  end.toUtc().toIso8601String())
            .order('logged_at', ascending: false);
        logs = (logRes as List).map((l) => MedicationLog.fromMap(l as Map<String, dynamic>)).toList();
        // Attach names
        final medMap = { for (var m in meds) m.id: m.name };
        for (final log in logs) { log.medicationName = medMap[log.medicationId]; }
      }

      if (mounted) setState(() { _medications = meds; _todayLogs = logs; _loading = false; });
    } catch (e) {
      debugPrint('Medication load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markTaken(Medication med) async {
    try {
      await Supabase.instance.client.from('medication_logs').insert({
        'medication_id': med.id,
        'status':        'taken',
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Set<String> get _takenTodayIds {
    final now    = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _todayLogs
        .where((l) => l.status == 'taken' && l.loggedAt.isAfter(todayStart))
        .map((l) => l.medicationId)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _kPrimary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: _kPrimary)))
          else ...[
            _buildTodaySection(),
            const SizedBox(height: 28),
            _buildLogSection(),
          ],
        ]),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Medication', style: TextStyle(fontFamily: 'League Spartan', fontSize: 28, fontWeight: FontWeight.w900, color: _kTextDark)),
            Text(DateFormat('EEEE, d MMMM').format(now), style: const TextStyle(fontSize: 16, color: _kTextGrey)),
          ]),
        ],
      ),
    );
  }

  // ─── Today Section ─────────────────────────────────────────────────────────
  Widget _buildTodaySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Today's Medicine", style: TextStyle(fontFamily: 'League Spartan', fontSize: 22, fontWeight: FontWeight.bold, color: _kTextDark)),
          Text('${_medications.length} item${_medications.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 16, color: _kTextGrey)),
        ]),
        const SizedBox(height: 16),
        if (_medications.isEmpty)
          _buildNoMedicineCard()
        else ...[
          ..._medications.map((med) => _buildMedicineCard(med)),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEditMedicineScreen())).then((_) => _load()),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Medicine', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ]
      ]),
    );
  }

  Widget _buildNoMedicineCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Icon(Icons.medication_outlined, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('No medicines added', style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Tap "Manage" to add your medications', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageMedicineScreen())).then((_) => _load()),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Medicine', style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ]),
    );
  }

  Widget _buildMedicineCard(Medication med) {
    final taken = _takenTodayIds.contains(med.id);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MedicineDetailScreen(medication: med))).then((_) => _load()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: taken ? _kPrimary.withOpacity(0.3) : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: _kBlue, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.medication_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(med.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextDark)),
              if (med.dosage != null) Text(med.dosage!, style: const TextStyle(fontSize: 16, color: _kTextGrey)),
            ])),
            if (taken)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _kPrimary.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                child: const Text('Taken ✓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _kPrimary)),
              ),
          ]),
          if (med.instruction != null || med.whenToTake != null) ...[
            const Divider(height: 20),
            Row(children: [
              if (med.whenToTake != null) ...[
                Icon(Icons.schedule_rounded, size: 18, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(med.whenToTake!, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                const SizedBox(width: 14),
              ],
              if (med.instruction != null) ...[
                Icon(Icons.restaurant_rounded, size: 18, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(med.instruction!, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              ],
            ]),
          ],
          if (!taken) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _markTaken(med),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('I have taken', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 10)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MedicineDetailScreen(medication: med))).then((_) => _load()),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: const Text('Details', style: TextStyle(color: _kTextGrey, fontSize: 16)),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  // ─── Log Section ───────────────────────────────────────────────────────────
  Widget _buildLogSection() {
    final takenLogs  = _todayLogs.where((l) => l.status == 'taken').toList();
    final missedLogs = _todayLogs.where((l) => l.status == 'missed').toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Text('Medication Log', style: TextStyle(fontFamily: 'League Spartan', fontSize: 22, fontWeight: FontWeight.bold, color: _kTextDark)),
      ),
      const SizedBox(height: 14),

      // Tab selector
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          height: 40,
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: ['Yesterday', 'Today', 'Tomorrow'].asMap().entries.map((e) {
              final sel = e.key == _logTab;
              return Expanded(
                child: GestureDetector(
                  onTap: () { setState(() => _logTab = e.key); _load(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: sel ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)] : [],
                    ),
                    alignment: Alignment.center,
                    child: Text(e.value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sel ? _kTextDark : Colors.black54)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 20),

      if (_todayLogs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(child: Text('No logs for this period', style: TextStyle(color: Colors.grey.shade400))),
        )
      else ...[
        if (missedLogs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Text('Missed Doses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFE53935))),
          ),
          const SizedBox(height: 8),
          ...missedLogs.map((l) => _buildLogCard(l, isMissed: true)),
          const SizedBox(height: 16),
        ],
        if (takenLogs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Text('Taken Doses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kPrimary)),
          ),
          const SizedBox(height: 8),
          ...takenLogs.map((l) => _buildLogCard(l, isMissed: false)),
        ],
      ],
    ]);
  }

  Widget _buildLogCard(MedicationLog log, {required bool isMissed}) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMissed ? const Color(0xFFFFF0F0) : const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMissed ? Colors.red.shade100 : Colors.green.shade100),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isMissed ? Colors.red.shade50 : _kPrimary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(isMissed ? Icons.close_rounded : Icons.check_rounded, color: isMissed ? Colors.red : _kPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(log.medicationName ?? 'Medicine', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kTextDark)),
            Text(DateFormat('hh:mm a').format(log.loggedAt), style: const TextStyle(fontSize: 14, color: _kTextGrey)),
          ]),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isMissed ? Colors.red.shade100 : _kPrimary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(isMissed ? 'Missed' : 'Taken', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isMissed ? Colors.red.shade700 : _kPrimary)),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MANAGE MEDICINE SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class ManageMedicineScreen extends StatefulWidget {
  const ManageMedicineScreen({super.key});
  @override State<ManageMedicineScreen> createState() => _ManageMedicineScreenState();
}

class _ManageMedicineScreenState extends State<ManageMedicineScreen> {
  List<Medication> _medications = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final schedRes = await Supabase.instance.client.from('schedule').select('schedule_id').eq('elderly_id', uid);
      final ids = (schedRes as List).map((s) => s['schedule_id'] as String).toList();
      List<Medication> meds = [];
      if (ids.isNotEmpty) {
        final medRes = await Supabase.instance.client.from('medications').select().inFilter('schedule_id', ids);
        meds = (medRes as List).map((m) => Medication.fromMap(m as Map<String, dynamic>)).toList();
      }
      if (mounted) setState(() { _medications = meds; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Medication med) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Medicine'),
      content: Text('Delete "${med.name}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok == true) {
      await Supabase.instance.client.from('medications').delete().eq('medication_id', med.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: _kTextDark), onPressed: () => Navigator.pop(context)),
        title: const Text('Manage Medicine', style: TextStyle(fontFamily: 'League Spartan', fontWeight: FontWeight.w900, color: _kTextDark, fontSize: 20)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, color: _kPrimary, size: 28),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEditMedicineScreen())).then((_) => _load()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              color: _kPrimary,
              onRefresh: _load,
              child: _medications.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      Center(child: Column(children: [
                        Icon(Icons.medication_outlined, size: 72, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No medicines yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('Tap + to add your first medicine', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                      ])),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _medications.length,
                      itemBuilder: (_, i) => _buildMedCard(_medications[i]),
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEditMedicineScreen())).then((_) => _load()),
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Medicine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildMedCard(Medication med) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)]),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: _kBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.medication_rounded, color: _kBlue, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(med.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextDark)),
          if (med.dosage != null) Text(med.dosage!, style: const TextStyle(fontSize: 16, color: _kTextGrey)),
          if (med.whenToTake != null) Text(med.whenToTake!, style: const TextStyle(fontSize: 16, color: _kTextGrey)),
        ])),
        Row(children: [
          if (med.stock != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (med.stock! < 5 ? Colors.red : _kPrimary).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${med.stock} left', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: med.stock! < 5 ? Colors.red : _kPrimary)),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'edit')   Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditMedicineScreen(existing: med))).then((_) => _load());
              if (val == 'delete') _delete(med);
              if (val == 'detail') Navigator.push(context, MaterialPageRoute(builder: (_) => MedicineDetailScreen(medication: med)));
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'detail', child: Row(children: [Icon(Icons.info_outline, size: 18), SizedBox(width: 8), Text('Details')])),
              const PopupMenuItem(value: 'edit',   child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: _kBlue), SizedBox(width: 8), Text('Edit')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
            ],
            icon: const Icon(Icons.more_vert, color: _kTextGrey),
          ),
        ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ADD / EDIT MEDICINE SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class AddEditMedicineScreen extends StatefulWidget {
  final Medication? existing;
  const AddEditMedicineScreen({super.key, this.existing});
  @override State<AddEditMedicineScreen> createState() => _AddEditMedicineScreenState();
}

class _AddEditMedicineScreenState extends State<AddEditMedicineScreen> {
  final _nameCtrl    = TextEditingController();
  final _dosageCtrl  = TextEditingController();
  final _stockCtrl   = TextEditingController();
  final _notesCtrl   = TextEditingController();
  String? _whenToTake;
  String? _instruction;
  String? _priority;
  DateTime? _expirationDate;
  bool  _saving = false;
  bool  _checkingAllergy = false;

  static const _whenToTakes   = ['Morning', 'Afternoon', 'Evening', 'Night', 'As needed'];
  static const _instructions  = ['Before meal', 'After meal', 'With meal', 'Before sleep', 'With water', 'As directed'];
  static const _priorities    = ['High', 'Medium', 'Low'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text   = e.name;
      _dosageCtrl.text = e.dosage ?? '';
      _stockCtrl.text  = e.stock?.toString() ?? '';
      _notesCtrl.text  = e.notes ?? '';
      _whenToTake      = e.whenToTake;
      _instruction     = e.instruction;
      _priority        = e.priority;
      _expirationDate  = e.expirationDate;
    }
  }

  @override void dispose() { _nameCtrl.dispose(); _dosageCtrl.dispose(); _stockCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  // ─── Allergy check via web search ─────────────────────────────────────────
  Future<void> _checkAllergy() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter medicine name first'))); return; }
    setState(() { _checkingAllergy = true; });

    // Get user's allergy info from the database
    String? userAllergies;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        // Fetch specific allergies from the new allergy_list table
        final res = await Supabase.instance.client
            .from('allergy_list')
            .select('allergy(name)')
            .eq('elderly_id', uid);

        final List<String> fetchedAllergies = [];
        for (var row in (res as List)) {
          final allergyData = row['allergy'];
          if (allergyData != null && allergyData['name'] != null) {
            fetchedAllergies.add(allergyData['name'] as String);
          }
        }
        if (fetchedAllergies.isNotEmpty) {
          userAllergies = fetchedAllergies.join(', ');
        }
      }
    } catch (e) {
      debugPrint('Error fetching allergies: $e');
    }

    if (mounted) {
      setState(() { _checkingAllergy = false; });
      _showAllergySheet(name, userAllergies);
    }
  }

  void _showAllergySheet(String medicineName, String? userAllergies) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AllergyAlertSheet(
        medicineName: medicineName,
        userAllergies: userAllergies,
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medicine name is required'))); return; }
    setState(() => _saving = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');

      // Ensure a schedule row exists for this user
      final schedRes = await Supabase.instance.client
          .from('schedule')
          .select('schedule_id')
          .eq('elderly_id', uid)
          .limit(1)
          .maybeSingle();

      String scheduleId;
      if (schedRes != null) {
        scheduleId = schedRes['schedule_id'] as String;
      } else {
        final newSched = await Supabase.instance.client.from('schedule').insert({
          'elderly_id': uid,
          'title': 'My Medications',
          'schedule_date_time': DateTime.now().toUtc().toIso8601String(),
        }).select('schedule_id').single();
        scheduleId = newSched['schedule_id'] as String;
      }

      final data = {
        'medication_name':  name,
        if (_dosageCtrl.text.trim().isNotEmpty)   'dosage':           _dosageCtrl.text.trim(),
        if (_whenToTake != null)                  'when_to_take':     _whenToTake,
        if (_instruction != null)                 'instruction':      _instruction,
        if (_stockCtrl.text.trim().isNotEmpty)    'medication_stock': int.tryParse(_stockCtrl.text.trim()),
        if (_notesCtrl.text.trim().isNotEmpty)    'medical_notes':    _notesCtrl.text.trim(),
        if (_priority != null)                    'priority':         _priority,
        if (_expirationDate != null)              'expiration_date':  _expirationDate!.toIso8601String().split('T').first,
        'schedule_id': scheduleId,
      };

      if (widget.existing != null) {
        await Supabase.instance.client.from('medications').update(data).eq('medication_id', widget.existing!.id);
      } else {
        await Supabase.instance.client.from('medications').insert(data);
      }

      // Schedule a local notification reminder
      if (_whenToTake != null) {
        await showMedicationReminder(
          name:        name,
          dosage:      _dosageCtrl.text.trim().isNotEmpty ? _dosageCtrl.text.trim() : '',
          instruction: _instruction ?? 'as directed',
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: _kTextDark), onPressed: () => Navigator.pop(context)),
        title: Text(isEdit ? 'Edit Medicine' : 'Add Medicine', style: const TextStyle(fontFamily: 'League Spartan', fontWeight: FontWeight.w900, color: _kTextDark, fontSize: 20)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Medicine name + allergy check
          _label('Medicine Name *'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                decoration: _inputDeco('e.g. Paracetamol'),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _checkingAllergy ? null : _checkAllergy,
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
                child: _checkingAllergy
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                    : const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Tap ⚠️ to check allergy info', style: TextStyle(fontSize: 11, color: Colors.orange.shade600)),
          const SizedBox(height: 16),

          _label('Dosage'),
          TextField(controller: _dosageCtrl, decoration: _inputDeco('e.g. 500mg, 1 tablet')),
          const SizedBox(height: 16),

          _label('When to take'),
          _dropdown('Select time', _whenToTakes, _whenToTake, (v) => setState(() => _whenToTake = v)),
          const SizedBox(height: 16),

          _label('Instruction'),
          _dropdown('Select instruction', _instructions, _instruction, (v) => setState(() => _instruction = v)),
          const SizedBox(height: 16),

          _label('Stock (number of pills)'),
          TextField(controller: _stockCtrl, keyboardType: TextInputType.number, decoration: _inputDeco('e.g. 30')),
          const SizedBox(height: 16),

          _label('Medical Notes'),
          TextField(controller: _notesCtrl, maxLines: 3, decoration: _inputDeco('Any notes about this medicine...')),
          const SizedBox(height: 16),
          
          _label('Expiration Date'),
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _expirationDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (d != null) setState(() => _expirationDate = d);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_expirationDate == null ? 'Select Date' : DateFormat('dd MMM yyyy').format(_expirationDate!), style: TextStyle(fontSize: 16, color: _expirationDate == null ? Colors.grey.shade400 : _kTextDark)),
                const Icon(Icons.calendar_today, size: 18, color: _kTextGrey),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          _label('Priority'),
          _dropdown('Select priority', _priorities, _priority, (v) => setState(() => _priority = v)),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Text(isEdit ? 'Update Medicine' : 'Save Medicine', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontFamily: 'Open Sans', fontSize: 14, fontWeight: FontWeight.w600, color: _kTextGrey)));

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
    filled: true, fillColor: Colors.white,
  );

  Widget _dropdown(String hint, List<String> items, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(hint, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
        filled: true, fillColor: Colors.white,
      ),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
      onChanged: onChanged,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MEDICINE DETAIL SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class MedicineDetailScreen extends StatelessWidget {
  final Medication medication;
  const MedicineDetailScreen({super.key, required this.medication});

  @override
  Widget build(BuildContext context) {
    final med = medication;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: _kTextDark), onPressed: () => Navigator.pop(context)),
        title: const Text('Medicine Details', style: TextStyle(fontFamily: 'League Spartan', fontWeight: FontWeight.w900, color: _kTextDark, fontSize: 20)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: _kBlue),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditMedicineScreen(existing: med))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Hero card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kBlue, Color(0xFF1A78C2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.medication_rounded, color: Colors.white, size: 42),
              ),
              const SizedBox(height: 16),
              Text(med.name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              if (med.dosage != null) Text(med.dosage!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ]),
          ),

          const SizedBox(height: 20),

          // Details card
          _infoCard([
            _infoRow(Icons.schedule_rounded,      'When to take', med.whenToTake ?? 'Not specified'),
            _infoRow(Icons.restaurant_rounded,    'Instruction',  med.instruction  ?? 'Not specified'),
            _infoRow(Icons.inventory_2_rounded,   'Stock',        med.stock != null ? '${med.stock} tablets remaining' : 'Not tracked'),
            if (med.expirationDate != null)
              _infoRow(Icons.event_busy_rounded,  'Expires',      DateFormat('dd MMM yyyy').format(med.expirationDate!)),
            if (med.priority != null)
              _infoRow(Icons.flag_rounded,        'Priority',     med.priority!),
            if (med.notes?.isNotEmpty == true)
              _infoRow(Icons.notes_rounded,       'Notes',        med.notes!),
          ]),

          const SizedBox(height: 16),

          // Stock warning
          if (med.stock != null && med.stock! < 5)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [
                const Icon(Icons.warning_rounded, color: Colors.red, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text('Low stock! Only ${med.stock} tablet${med.stock == 1 ? '' : 's'} remaining. Please refill soon.', style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600))),
              ]),
            ),

          const SizedBox(height: 16),

          // Check allergy button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent('${med.name} allergy side effects')}');
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  debugPrint('Could not launch url: $e');
                }
              },
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              label: const Text('Check Allergy & Side Effects', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Send reminder button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await showMedicationReminder(name: med.name, dosage: med.dosage ?? '', instruction: med.instruction ?? 'as directed');
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder sent! 💊'), backgroundColor: _kPrimary));
              },
              icon: const Icon(Icons.notifications_rounded, color: Colors.white),
              label: const Text('Send Reminder Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: rows),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: _kPrimary, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _kTextGrey, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kTextDark)),
        ])),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ALLERGY ALERT BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════
class AllergyAlertSheet extends StatelessWidget {
  final String  medicineName;
  final String? userAllergies;

  const AllergyAlertSheet({super.key, required this.medicineName, this.userAllergies});

  // Common allergy keywords — basic client-side check
  static const _knownAllergens = {
    'penicillin':    ['amoxicillin', 'ampicillin', 'flucloxacillin'],
    'aspirin':       ['ibuprofen', 'naproxen', 'diclofenac', 'mefenamic'],
    'sulfa':         ['sulfamethoxazole', 'trimethoprim'],
    'codeine':       ['morphine', 'tramadol', 'oxycodone'],
    'erythromycin':  ['azithromycin', 'clarithromycin'],
  };

  bool get _hasPotentialConflict {
    if (userAllergies == null || userAllergies!.isEmpty) return false;
    final allergyLower = userAllergies!.toLowerCase();
    final medLower     = medicineName.toLowerCase();
    // Direct match
    if (allergyLower.contains(medLower)) return true;
    // Class-based check
    for (final entry in _knownAllergens.entries) {
      if (allergyLower.contains(entry.key)) {
        if (entry.value.any((rel) => medLower.contains(rel))) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final conflict = _hasPotentialConflict;
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),

        // Icon
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: conflict ? Colors.red.shade50 : Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            conflict ? Icons.warning_rounded : Icons.check_circle_rounded,
            color: conflict ? Colors.red : Colors.green,
            size: 48,
          ),
        ),
        const SizedBox(height: 16),

        Text(
          conflict ? 'Potential Allergy Alert!' : 'No Known Conflicts',
          style: TextStyle(fontFamily: 'League Spartan', fontSize: 22, fontWeight: FontWeight.w900, color: conflict ? Colors.red : Colors.green.shade700),
        ),
        const SizedBox(height: 8),

        Text(
          medicineName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kTextDark),
        ),
        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: conflict ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: conflict ? Colors.red.shade200 : Colors.green.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (userAllergies?.isNotEmpty == true) ...[
              Text('Your recorded allergies:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(userAllergies!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: conflict ? Colors.red.shade700 : _kTextDark)),
              const SizedBox(height: 12),
            ],
            Text(
              conflict
                  ? '⚠️ "$medicineName" may conflict with your known allergies. Please consult your doctor before taking this medicine.'
                  : '✅ No direct conflict found between "$medicineName" and your recorded allergies. Always consult your doctor if unsure.',
              style: TextStyle(fontSize: 13, color: conflict ? Colors.red.shade700 : Colors.green.shade800, height: 1.5),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // Web search for more info
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent('$medicineName allergy information side effects')}');
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                debugPrint('Could not launch url: $e');
              }
            },
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('Search More Info Online'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _kBlue),
              foregroundColor: _kBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: conflict ? Colors.red : _kPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(conflict ? 'I Understand, Proceed with Caution' : 'Got it', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}
