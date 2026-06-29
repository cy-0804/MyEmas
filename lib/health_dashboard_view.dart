import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import 'session_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ai_health_service.dart';

// ─── colour tokens ───────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF51A77B);
const _kBlue = Color(0xFF00539E);
const _kBg = Color(0xFFF6F8FA);
const _kCard = Colors.white;
const _kTextDark = Color(0xFF27252E);
const _kTextGrey = Color(0xFF6C7278);

// ─── models ──────────────────────────────────────────────────────────────────
class HealthRecord {
  final String id;
  final String? bloodPressure;
  final int? heartRate;
  final double? glucoseLevel;
  final double? temperature;
  final String? mood;
  final DateTime recordedAt;

  HealthRecord({
    required this.id,
    this.bloodPressure,
    this.heartRate,
    this.glucoseLevel,
    this.temperature,
    this.mood,
    required this.recordedAt,
  });

  factory HealthRecord.fromMap(Map<String, dynamic> m) {
    String dtStr = m['recorded_at'] as String;
    if (!dtStr.endsWith('Z')) dtStr += 'Z';
    return HealthRecord(
      id: m['record_id'] as String,
      bloodPressure: m['blood_pressure'] as String?,
      heartRate: m['heart_rate'] as int?,
      glucoseLevel: (m['glucose_level'] as num?)?.toDouble(),
      temperature: (m['temperature'] as num?)?.toDouble(),
      mood: m['mood'] as String?,
      recordedAt: DateTime.parse(dtStr).toLocal(),
    );
  }

  Map<String, dynamic> toInsertMap(String elderlyId) => {
    'elderly_id': elderlyId,
    if (bloodPressure != null) 'blood_pressure': bloodPressure,
    if (heartRate != null) 'heart_rate': heartRate,
    if (glucoseLevel != null) 'glucose_level': glucoseLevel,
    if (temperature != null) 'temperature': temperature,
    if (mood != null) 'mood': mood,
  };
}

// ─── helper: blood pressure status ───────────────────────────────────────────
({String label, Color color}) _bpStatus(String? bp) {
  if (bp == null || bp.isEmpty) return (label: '–', color: Colors.grey);
  final parts = bp.split('/');
  if (parts.length != 2) return (label: bp, color: Colors.grey);
  final sys = int.tryParse(parts[0].trim()) ?? 0;
  if (sys < 90) return (label: 'Low'.tr(), color: Colors.blue);
  if (sys < 120) return (label: 'Normal'.tr(), color: _kPrimary);
  if (sys < 130) return (label: 'Elevated'.tr(), color: Colors.orange);
  return (label: 'High'.tr(), color: Colors.red);
}

Color _hrColor(int? hr) {
  if (hr == null) return Colors.grey;
  if (hr < 60 || hr > 100) return Colors.orange;
  return _kPrimary;
}

Color _glucoseColor(double? g) {
  if (g == null) return Colors.grey;
  if (g < 3.9 || g > 7.8) return Colors.orange;
  return _kPrimary;
}

Color _tempColor(double? t) {
  if (t == null) return Colors.grey;
  if (t < 36.0 || t > 37.5) return Colors.orange;
  return _kPrimary;
}

// ═════════════════════════════════════════════════════════════════════════════
// Main HealthDashboardView
// ═════════════════════════════════════════════════════════════════════════════
class HealthDashboardView extends StatefulWidget {
  const HealthDashboardView({super.key});
  @override
  State<HealthDashboardView> createState() => _HealthDashboardViewState();
}

class _HealthDashboardViewState extends State<HealthDashboardView> {
  final _db = Supabase.instance.client;

  List<HealthRecord> _records = [];
  bool _loading = true;
  String? _elderlyId;
  String? _healthRecordTime;
  bool _timePromptShown = false;

  // History view state
  int _historyTab = 0; // 0=Day, 1=Week, 2=Month
  String _filterMetric = 'Blood Pressure';
  static const _tabs = ['Day', 'Week', 'Month'];
  static const _metrics = [
    'Blood Pressure',
    'Heart Rate',
    'Glucose',
    'Temperature',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      _elderlyId = uid;

      DateTime start;
      final now = DateTime.now();
      if (_historyTab == 0) {
        start = DateTime(now.year, now.month, now.day);
      } else if (_historyTab == 1) {
        start = now.subtract(const Duration(days: 6));
      } else {
        start = DateTime(now.year, now.month, 1);
      }

      final res = await _db
          .from('health_record')
          .select()
          .eq('elderly_id', uid)
          .gte('recorded_at', start.toUtc().toIso8601String())
          .order('recorded_at', ascending: false);

      if (mounted) {
        setState(() {
          _records = (res as List)
              .map((m) => HealthRecord.fromMap(m as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
        // Check health record time without awaiting to not block UI
        _checkHealthRecordTime(uid);
      }
    } catch (e) {
      debugPrint('HealthDash load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkHealthRecordTime(String uid) async {
    if (_timePromptShown) return;
    try {
      final res = await _db
          .from('elderly')
          .select('health_record_time')
          .eq('user_id', uid)
          .maybeSingle();
      if (res != null) {
        if (mounted) {
          setState(
            () => _healthRecordTime = res['health_record_time'] as String?,
          );
        }
      }

      if (_healthRecordTime == null && mounted) {
        _timePromptShown = true;
        _showTimeSetupDialog(uid);
      }
    } catch (e) {
      // Ignored: column might not exist yet if user hasn't run the SQL migration
      debugPrint('Health record time check error: $e');
    }
  }

  void _showTimeSetupDialog(String uid) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Set Health Record Time'.tr(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'You have not set a daily time to record your health data. When would you like to be reminded?'
                .tr(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: Text(
                'Skip'.tr(),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                );
                if (time != null) {
                  final formattedTime =
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
                  try {
                    await _db
                        .from('elderly')
                        .update({'health_record_time': formattedTime})
                        .eq('user_id', uid);
                    if (mounted) {
                      setState(() => _healthRecordTime = formattedTime);
                    }
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Time saved successfully!'.tr())),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving time: $e'.tr())),
                    );
                  }
                }
              },
              child: Text('Set Time'.tr()),
            ),
          ],
        );
      },
    );
  }

  List<HealthRecord> get _todayRecords {
    final now = DateTime.now();
    return _records
        .where(
          (r) =>
              r.recordedAt.year == now.year &&
              r.recordedAt.month == now.month &&
              r.recordedAt.day == now.day,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _kPrimary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 160),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            if (_loading)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: _kPrimary),
                ),
              )
            else ...[
              _buildTodaySection(),
              const SizedBox(height: 28),
              _buildHistorySection(),
            ],
          ],
        ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health'.tr(),
                style: const TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _kTextDark,
                ),
              ),
              Text(
                DateFormat('EEEE, d MMMM').format(now),
                style: const TextStyle(fontSize: 16, color: _kTextGrey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Today Section ─────────────────────────────────────────────────────────
  Widget _buildTodaySection() {
    final todayRecs = _todayRecords;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Today's Health".tr(),
                style: const TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _kTextDark,
                ),
              ),
              if (todayRecs.isNotEmpty)
                GestureDetector(
                  onTap: () => _navigateToTodayHealth(),
                  child: Text(
                    'View All'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _kPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (todayRecs.isEmpty)
            _buildNoDataCard()
          else ...[
            Builder(
              builder: (ctx) {
                final r = todayRecs.first;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          _buildMetricCard(
                            'Blood Pressure'.tr(),
                            r.bloodPressure ?? '–',
                            'mmHg'.tr(),
                            Icons.show_chart,
                            Colors.blue.shade600,
                            Colors.blue.shade50,
                          ),
                          _buildMetricCard(
                            'Heart Rate'.tr(),
                            r.heartRate?.toString() ?? '–',
                            'bpm'.tr(),
                            Icons.favorite_border,
                            Colors.red.shade400,
                            Colors.red.shade50,
                          ),
                          _buildMetricCard(
                            'Glucose Level'.tr(),
                            r.glucoseLevel?.toStringAsFixed(1) ?? '–',
                            'mmol/L'.tr(),
                            Icons.bloodtype,
                            Colors.green.shade600,
                            Colors.green.shade50,
                          ),
                          _buildMetricCard(
                            'Temperature'.tr(),
                            r.temperature?.toStringAsFixed(1) ?? '–',
                            '°C'.tr(),
                            Icons.thermostat,
                            Colors.grey.shade700,
                            Colors.grey.shade200,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Center(
                        child: ElevatedButton(
                          onPressed: () => _showAddRecordSheet(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Add New Record'.tr(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          '${'Latest Update'.tr()}: ${DateFormat('h:mm a').format(todayRecs.first.recordedAt)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _kPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoDataCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.monitor_heart_outlined,
            size: 56,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            'No health data today'.tr(),
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Record" to log your health data'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _showAddRecordSheet(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              'Add Record'.tr(),
              style: const TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String unit,
    IconData icon,
    Color iconColor,
    Color iconBg,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kTextDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w400,
                  color: _kTextDark,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: const TextStyle(fontSize: 18, color: _kTextDark),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── History Section ────────────────────────────────────────────────────────
  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Health History'.tr(),
                style: const TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _kTextDark,
                ),
              ),
              GestureDetector(
                onTap: () => _navigateToHistory(),
                child: Text(
                  'View All'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _kPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Tab selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: _tabs.asMap().entries.map((e) {
                final sel = e.key == _historyTab;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _historyTab = e.key);
                      _load();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: sel ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 4,
                                ),
                              ]
                            : [],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        e.value.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: sel ? _kTextDark : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Metric filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: _metrics.map((m) {
              final sel = m == _filterMetric;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filterMetric = m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _kPrimary.withOpacity(0.12) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? _kPrimary : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      m.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: sel ? _kPrimary : Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // Chart
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 200,
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _records.isEmpty
                ? Center(
                    child: Text(
                      'No data'.tr(),
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  )
                : _buildChart(),
          ),
        ),
        const SizedBox(height: 20),

        // Record list
        Builder(
          builder: (ctx) {
            final filtered = _records.where((r) {
              if (_filterMetric == 'Blood Pressure') {
                return r.bloodPressure != null;
              }
              if (_filterMetric == 'Heart Rate') return r.heartRate != null;
              if (_filterMetric == 'Glucose') return r.glucoseLevel != null;
              if (_filterMetric == 'Temperature') return r.temperature != null;
              return true;
            }).toList();

            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: Text(
                    'No records for $_filterMetric in this period'.tr(),
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
              );
            }
            return Column(children: _buildGroupedCardsList(filtered));
          },
        ),
      ],
    );
  }

  Widget _buildChart() {
    List<FlSpot> spots = [];
    for (int i = 0; i < _records.length && i < 10; i++) {
      final r = _records[_records.length - 1 - i]; // oldest first
      double? val;
      switch (_filterMetric) {
        case 'Blood Pressure':
          final parts = r.bloodPressure?.split('/');
          if (parts != null && parts.length == 2) {
            val = double.tryParse(parts[0].trim());
          }
          break;
        case 'Heart Rate':
          val = r.heartRate?.toDouble();
          break;
        case 'Glucose':
          val = r.glucoseLevel;
          break;
        case 'Temperature':
          val = r.temperature;
          break;
      }
      if (val != null) spots.add(FlSpot(i.toDouble(), val));
    }

    if (spots.isEmpty) {
      return Center(
        child: Text(
          'No data'.tr(),
          style: TextStyle(color: Colors.grey.shade400),
        ),
      );
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 5;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 5;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade100, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= _records.length) {
                  return const SizedBox.shrink();
                }
                final rec = _records[_records.length - 1 - idx];
                String label;
                if (_historyTab == 0) {
                  label = DateFormat('HH:mm').format(rec.recordedAt);
                } else if (_historyTab == 1)
                  label = DateFormat('EEE').format(rec.recordedAt);
                else
                  label = DateFormat('d').format(rec.recordedAt);
                return SideTitleWidget(
                  meta: m,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: (maxY - minY) / 4,
              getTitlesWidget: (v, m) => SideTitleWidget(
                meta: m,
                child: Text(
                  v.toStringAsFixed(0),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble().clamp(1, 9),
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _kPrimary,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (sp, pct, bd, i) => FlDotCirclePainter(
                radius: 3,
                color: _kPrimary,
                strokeWidth: 0,
                strokeColor: Colors.transparent,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: _kPrimary.withOpacity(0.06),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedCardsList(List<HealthRecord> records) {
    Map<String, List<HealthRecord>> grouped = {};
    for (final r in records.reversed) {
      String d = DateFormat('d MMM yyyy').format(r.recordedAt);
      if (!grouped.containsKey(d)) grouped[d] = [];
      grouped[d]!.add(r);
    }
    return grouped.entries
        .map((e) => _buildDashboardGroupCard(e.key, e.value))
        .toList();
  }

  Widget _buildDashboardGroupCard(String dateStr, List<HealthRecord> records) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: _kTextDark,
            ),
          ),
          const Divider(height: 16),
          ...records.map((r) => _buildDashboardTimeRow(r)),
        ],
      ),
    );
  }

  Widget _buildDashboardTimeRow(HealthRecord r) {
    String val = '–';
    Color c = Colors.grey;
    IconData icon = Icons.circle;

    if (_filterMetric == 'Blood Pressure') {
      val = r.bloodPressure?.isNotEmpty == true
          ? '${r.bloodPressure} mmHg'.tr()
          : '–';
      c = _bpStatus(r.bloodPressure).color;
      icon = Icons.show_chart;
    } else if (_filterMetric == 'Heart Rate') {
      val = r.heartRate != null ? '${r.heartRate} bpm'.tr() : '–';
      c = _hrColor(r.heartRate);
      icon = Icons.favorite;
    } else if (_filterMetric == 'Glucose') {
      val = r.glucoseLevel != null
          ? '${r.glucoseLevel!.toStringAsFixed(1)} mmol/L'.tr()
          : '–';
      c = _glucoseColor(r.glucoseLevel);
      icon = Icons.bloodtype;
    } else if (_filterMetric == 'Temperature') {
      val = r.temperature != null
          ? '${r.temperature!.toStringAsFixed(1)} °C'.tr()
          : '–';
      c = _tempColor(r.temperature);
      icon = Icons.thermostat;
    }

    if (val == '–') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            DateFormat('h:mm a').format(r.recordedAt),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _kTextGrey,
            ),
          ),
          Row(
            children: [
              Text(
                val,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: c,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 20, color: c),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Navigation ─────────────────────────────────────────────────────────────
  void _navigateToTodayHealth() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodayHealthScreen(
          records: _todayRecords,
          elderlyId: _elderlyId ?? '',
        ),
      ),
    ).then((_) => _load());
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HealthHistoryScreen(elderlyId: _elderlyId ?? ''),
      ),
    ).then((_) => _load());
  }

  // ─── Add / Edit Sheets ──────────────────────────────────────────────────────
  void _showAddRecordSheet(BuildContext ctx) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditHealthRecordScreen(elderlyId: _elderlyId ?? ''),
      ),
    );
    _load();
  }

  void _showEditSheet(BuildContext ctx, HealthRecord r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddEditHealthRecordScreen(elderlyId: _elderlyId ?? '', existing: r),
      ),
    );
    _load();
  }

  Future<void> _confirmDelete(BuildContext ctx, HealthRecord r) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text('Delete Record'.tr()),
        content: Text('Are you sure you want to delete this record?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete'.tr(),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('health_record')
          .delete()
          .eq('record_id', r.id);
      _load();
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Add / Edit Health Record Screen
// ═════════════════════════════════════════════════════════════════════════════
class AddEditHealthRecordScreen extends StatefulWidget {
  final String elderlyId;
  final HealthRecord? existing;
  const AddEditHealthRecordScreen({
    super.key,
    required this.elderlyId,
    this.existing,
  });
  @override
  State<AddEditHealthRecordScreen> createState() =>
      _AddEditHealthRecordScreenState();
}

class _AddEditHealthRecordScreenState extends State<AddEditHealthRecordScreen> {
  final _bpCtrl = TextEditingController();
  final _hrCtrl = TextEditingController();
  final _glucCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _bpCtrl.text = e.bloodPressure ?? '';
      _hrCtrl.text = e.heartRate?.toString() ?? '';
      _glucCtrl.text = e.glucoseLevel?.toString() ?? '';
      _tempCtrl.text = e.temperature?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _bpCtrl.dispose();
    _hrCtrl.dispose();
    _glucCtrl.dispose();
    _tempCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.tr()), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _save() async {
    final bp = _bpCtrl.text.trim();
    if (bp.isNotEmpty) {
      final parts = bp.split('/');
      if (parts.length != 2) {
        _showError('Blood Pressure must be in format SYS/DIA (e.g., 120/80)');
        return;
      }
      final sys = int.tryParse(parts[0]);
      final dia = int.tryParse(parts[1]);
      if (sys == null ||
          dia == null ||
          sys < 50 ||
          sys > 250 ||
          dia < 30 ||
          dia > 150) {
        _showError('Systolic must be 50-250 and Diastolic must be 30-150 mmHg');
        return;
      }
    }

    final hrStr = _hrCtrl.text.trim();
    if (hrStr.isNotEmpty) {
      final hr = int.tryParse(hrStr);
      if (hr == null || hr < 30 || hr > 220) {
        _showError('Heart Rate must be between 30 and 220 bpm');
        return;
      }
    }

    final glucStr = _glucCtrl.text.trim();
    if (glucStr.isNotEmpty) {
      final gluc = double.tryParse(glucStr);
      if (gluc == null || gluc < 1.0 || gluc > 35.0) {
        _showError('Glucose Level must be between 1.0 and 35.0 mmol/L');
        return;
      }
    }

    final tempStr = _tempCtrl.text.trim();
    if (tempStr.isNotEmpty) {
      final temp = double.tryParse(tempStr);
      if (temp == null || temp < 34.0 || temp > 43.0) {
        _showError('Body Temperature must be between 34.0 and 43.0 °C');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final db = Supabase.instance.client;

      // Ensure the user exists in the elderly table (e.g. if they clicked 'Skip for now' on onboarding)
      final elderlyRes = await db
          .from('elderly')
          .select('user_id')
          .eq('user_id', widget.elderlyId)
          .limit(1)
          .maybeSingle();

      if (elderlyRes == null) {
        await db.from('elderly').insert({'user_id': widget.elderlyId});
      }

      final data = <String, dynamic>{
        'elderly_id': widget.elderlyId,
        if (_bpCtrl.text.trim().isNotEmpty)
          'blood_pressure': _bpCtrl.text.trim(),
        if (_hrCtrl.text.trim().isNotEmpty)
          'heart_rate': int.tryParse(_hrCtrl.text.trim()),
        if (_glucCtrl.text.trim().isNotEmpty)
          'glucose_level': double.tryParse(_glucCtrl.text.trim()),
        if (_tempCtrl.text.trim().isNotEmpty)
          'temperature': double.tryParse(_tempCtrl.text.trim()),
        if (widget.existing == null)
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
      };

      String recordId;
      if (widget.existing != null) {
        recordId = widget.existing!.id;
        await db.from('health_record').update(data).eq('record_id', recordId);
      } else {
        final res = await db
            .from('health_record')
            .insert(data)
            .select('record_id')
            .single();
        recordId = res['record_id'] as String;
      }

      // AI-based intelligent risk detection
      String riskLevel = 'low';
      String recommendation =
          'Vitals are within normal range. Continue maintaining a healthy lifestyle and regular check-ups.'
              .tr();

      try {
        final bpStr = _bpCtrl.text.trim();
        final hr = int.tryParse(_hrCtrl.text.trim());
        final gluc = double.tryParse(_glucCtrl.text.trim());
        final temp = double.tryParse(_tempCtrl.text.trim());

        final aiResult = await AiHealthService.evaluateImmediateRisk(
          elderlyId: widget.elderlyId,
          bloodPressure: bpStr.isEmpty ? null : bpStr,
          heartRate: hr,
          glucoseLevel: gluc,
          temperature: temp,
        );

        riskLevel = aiResult['risk_level']?.toString().toLowerCase() ?? 'low';
        recommendation =
            aiResult['recommendation']?.toString() ?? recommendation;

        // Ensure riskLevel is one of the valid enums just in case
        if (!['low', 'medium', 'high'].contains(riskLevel)) {
          riskLevel = 'low';
        }
      } catch (e) {
        debugPrint(
          "AI Risk Evaluation failed, falling back to basic rule: \$e",
        );
        // Simple fallback
        final sys = int.tryParse(
          _bpCtrl.text.trim().split('/').firstOrNull ?? '',
        );
        final hr = int.tryParse(_hrCtrl.text.trim());
        final gluc = double.tryParse(_glucCtrl.text.trim());
        if ((sys != null && sys > 180) ||
            (hr != null && (hr > 120 || hr < 50)) ||
            (gluc != null && (gluc > 15.0 || gluc < 3.9))) {
          riskLevel = 'high';
          recommendation =
              'Critical Warning: Immediate medical attention is required.'.tr();
        }
      }

      // Save automatic risk assessment
      final existingRisk = await db
          .from('health_risk_assessment')
          .select('risk_id')
          .eq('record_id', recordId)
          .maybeSingle();
      if (existingRisk != null) {
        await db
            .from('health_risk_assessment')
            .update({'risk_level': riskLevel, 'recommendation': recommendation})
            .eq('risk_id', existingRisk['risk_id']);
      } else {
        await db.from('health_risk_assessment').insert({
          'record_id': recordId,
          'risk_level': riskLevel,
          'recommendation': recommendation,
        });
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Edit Health Record'.tr() : 'Add Health Record'.tr(),
                style: const TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: _kTextDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isEdit
                    ? DateFormat(
                        'EEEE, d MMMM yyyy, hh:mm a',
                      ).format(widget.existing!.recordedAt)
                    : DateFormat(
                        'EEEE, d MMMM yyyy, hh:mm a',
                      ).format(DateTime.now()),
                style: const TextStyle(fontSize: 16, color: _kTextGrey),
              ),
              const SizedBox(height: 32),

              _fieldLabel('Blood Pressure'.tr(), Icons.show_chart),
              _textField(
                _bpCtrl,
                '120/80',
                TextInputType.text,
                suffix: 'mmHg'.tr(),
              ),
              const SizedBox(height: 24),

              _fieldLabel('Heart Rate'.tr(), Icons.favorite),
              _textField(
                _hrCtrl,
                '72',
                TextInputType.number,
                suffix: 'bpm'.tr(),
              ),
              const SizedBox(height: 24),

              _fieldLabel('Glucose Level'.tr(), Icons.bloodtype),
              _textField(
                _glucCtrl,
                '5.5',
                TextInputType.numberWithOptions(decimal: true),
                suffix: 'mmol/L'.tr(),
              ),
              const SizedBox(height: 24),

              _fieldLabel('Body Temperature'.tr(), Icons.thermostat),
              _textField(
                _tempCtrl,
                '36.5',
                TextInputType.numberWithOptions(decimal: true),
                suffix: '°C'.tr(),
              ),
              const SizedBox(height: 36),

              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : Text(
                          isEdit ? 'Update Record'.tr() : 'Save Record'.tr(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String t, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 24, color: _kTextGrey),
        const SizedBox(width: 8),
        Text(
          t,
          style: const TextStyle(
            fontFamily: 'Open Sans',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _kTextGrey,
          ),
        ),
      ],
    ),
  );

  Widget _textField(
    TextEditingController ctrl,
    String hint,
    TextInputType kt, {
    String? suffix,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: kt,
      style: const TextStyle(fontSize: 20, color: _kTextDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 18),
        suffixText: suffix,
        suffixStyle: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimary, width: 2),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Today Health Screen (full list of today's records)
// ═════════════════════════════════════════════════════════════════════════════
class TodayHealthScreen extends StatefulWidget {
  final List<HealthRecord> records;
  final String elderlyId;
  const TodayHealthScreen({
    super.key,
    required this.records,
    required this.elderlyId,
  });

  @override
  State<TodayHealthScreen> createState() => _TodayHealthScreenState();
}

class _TodayHealthScreenState extends State<TodayHealthScreen> {
  late List<HealthRecord> _records;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _records = List.from(widget.records);
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    try {
      final res = await Supabase.instance.client
          .from('health_record')
          .select()
          .eq('elderly_id', widget.elderlyId)
          .gte('recorded_at', start.toUtc().toIso8601String())
          .order('recorded_at', ascending: false);
      if (mounted) {
        setState(() {
          _records = (res as List)
              .map((m) => HealthRecord.fromMap(m as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {}
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      final dt = DateTime(2020, 1, 1, time.hour, time.minute);
      final str = DateFormat('hh:mm a').format(dt);
      setState(() {
        _searchQuery = str;
        _searchCtrl.text = str;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showEditSheet(HealthRecord r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddEditHealthRecordScreen(elderlyId: widget.elderlyId, existing: r),
      ),
    );
    _load();
  }

  Future<void> _confirmDelete(HealthRecord r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete Record'.tr()),
        content: Text('Are you sure you want to delete this record?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete'.tr(),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client
          .from('health_record')
          .delete()
          .eq('record_id', r.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredRecords = _records.where((r) {
      final timeStr = DateFormat('hh:mm a').format(r.recordedAt).toLowerCase();
      return timeStr.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Today's Health".tr(),
          style: const TextStyle(
            fontFamily: 'League Spartan',
            fontWeight: FontWeight.w900,
            color: _kTextDark,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search by time (e.g. 03:11 AM)'.tr(),
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time, color: Colors.grey),
                  onPressed: _pickTime,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: _kPrimary),
                ),
              ),
            ),
          ),
          Expanded(
            child: _records.isEmpty
                ? Center(
                    child: Text(
                      'No records today'.tr(),
                      style: const TextStyle(color: _kTextGrey),
                    ),
                  )
                : filteredRecords.isEmpty
                ? Center(
                    child: Text(
                      'No matching time'.tr(),
                      style: const TextStyle(color: _kTextGrey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: _buildGroupedBySession(filteredRecords),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedBySession(List<HealthRecord> records) {
    Map<String, List<HealthRecord>> grouped = {};
    final manager = SessionManager();
    for (final r in records) {
      final rTime = r.recordedAt.hour * 60 + r.recordedAt.minute;
      CustomSession? best;
      int minDiff = 24 * 60;
      for (final s in manager.sessions) {
        final sTime = s.time.hour * 60 + s.time.minute;
        final diff = (rTime - sTime).abs();
        if (diff < minDiff) {
          minDiff = diff;
          best = s;
        }
      }
      final sName = best?.name ?? 'Day';
      if (!grouped.containsKey(sName)) grouped[sName] = [];
      grouped[sName]!.add(r);
    }

    List<Widget> widgets = [];
    for (final s in manager.sessions) {
      if (grouped.containsKey(s.name)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0, top: 12.0),
            child: Row(
              children: [
                const Icon(Icons.wb_sunny_outlined, size: 20, color: _kPrimary),
                const SizedBox(width: 8),
                Text(
                  '${s.name} Session'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
        for (final r in grouped[s.name]!) {
          widgets.add(_buildDetailCard(r));
        }
      }
    }
    if (grouped.containsKey('Day')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0, top: 12.0),
          child: Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 20, color: _kPrimary),
              const SizedBox(width: 8),
              Text(
                'Day Session'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kPrimary,
                ),
              ),
            ],
          ),
        ),
      );
      for (final r in grouped['Day']!) {
        widgets.add(_buildDetailCard(r));
      }
    }

    return widgets;
  }

  Widget _buildDetailCard(HealthRecord r) {
    final bpSt = _bpStatus(r.bloodPressure);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('hh:mm a').format(r.recordedAt),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _kTextDark,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 24,
                      color: _kBlue,
                    ),
                    onPressed: () => _showEditSheet(r),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 24,
                      color: Colors.red,
                    ),
                    onPressed: () => _confirmDelete(r),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          _row(
            'Blood Pressure'.tr(),
            r.bloodPressure?.isNotEmpty == true
                ? '${r.bloodPressure} mmHg'.tr()
                : '–',
            bpSt.color,
            Icons.show_chart,
          ),
          _row(
            'Heart Rate'.tr(),
            r.heartRate != null ? '${r.heartRate} bpm'.tr() : '–',
            _hrColor(r.heartRate),
            Icons.favorite,
          ),
          _row(
            'Glucose Level'.tr(),
            r.glucoseLevel != null
                ? '${r.glucoseLevel!.toStringAsFixed(1)} mmol/L'.tr()
                : '–',
            _glucoseColor(r.glucoseLevel),
            Icons.bloodtype,
          ),
          _row(
            'Temperature'.tr(),
            r.temperature != null
                ? '${r.temperature!.toStringAsFixed(1)} °C'.tr()
                : '–',
            _tempColor(r.temperature),
            Icons.thermostat,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: _kTextGrey),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 18, color: _kTextDark),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Health History Screen (full screen with day/week/month tabs)
// ═════════════════════════════════════════════════════════════════════════════
class HealthHistoryScreen extends StatefulWidget {
  final String elderlyId;
  const HealthHistoryScreen({super.key, required this.elderlyId});
  @override
  State<HealthHistoryScreen> createState() => _HealthHistoryScreenState();
}

class _HealthHistoryScreenState extends State<HealthHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<HealthRecord> _records = [];
  bool _loading = true;
  String _metric = 'Blood Pressure';
  DateTime _selectedDate = DateTime.now();

  static const _metrics = [
    'Blood Pressure',
    'Heart Rate',
    'Glucose',
    'Temperature',
  ];
  static const _tabs = ['Day', 'Week', 'Month'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabCtrl.indexIsChanging) _load();
      });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    DateTime start;
    DateTime end;

    switch (_tabCtrl.index) {
      case 0:
        start = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        end = start.add(const Duration(days: 1));
        break;
      case 1:
        int weekday = _selectedDate.weekday; // 1 = Monday
        start = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day - (weekday - 1),
        );
        end = start.add(const Duration(days: 7));
        break;
      default:
        start = DateTime(_selectedDate.year, _selectedDate.month, 1);
        end = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
        break;
    }

    try {
      final res = await Supabase.instance.client
          .from('health_record')
          .select()
          .eq('elderly_id', widget.elderlyId)
          .gte('recorded_at', start.toUtc().toIso8601String())
          .lt('recorded_at', end.toUtc().toIso8601String())
          .order('recorded_at');
      if (mounted) {
        setState(() {
          _records = (res as List)
              .map((m) => HealthRecord.fromMap(m as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildDateSelector() {
    String label = '';
    if (_tabCtrl.index == 0) {
      label = DateFormat('d MMM yyyy').format(_selectedDate);
    } else if (_tabCtrl.index == 1) {
      int weekday = _selectedDate.weekday;
      DateTime start = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day - (weekday - 1),
      );
      DateTime end = start.add(const Duration(days: 6));
      label =
          '${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM yyyy').format(end)}';
    } else {
      label = DateFormat('MMMM yyyy').format(_selectedDate);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: _kPrimary, size: 30),
            onPressed: () {
              setState(() {
                if (_tabCtrl.index == 0) {
                  _selectedDate = _selectedDate.subtract(
                    const Duration(days: 1),
                  );
                } else if (_tabCtrl.index == 1) {
                  _selectedDate = _selectedDate.subtract(
                    const Duration(days: 7),
                  );
                } else {
                  _selectedDate = DateTime(
                    _selectedDate.year,
                    _selectedDate.month - 1,
                    _selectedDate.day,
                  );
                }
              });
              _load();
            },
          ),
          GestureDetector(
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDatePickerMode: _tabCtrl.index == 2
                    ? DatePickerMode.year
                    : DatePickerMode.day,
              );
              if (picked != null) {
                setState(() {
                  if (_tabCtrl.index == 2) {
                    _selectedDate = DateTime(picked.year, picked.month, 1);
                  } else {
                    _selectedDate = picked;
                  }
                });
                _load();
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kTextDark,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: _kTextDark),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: _kPrimary, size: 30),
            onPressed: () {
              setState(() {
                if (_tabCtrl.index == 0) {
                  _selectedDate = _selectedDate.add(const Duration(days: 1));
                } else if (_tabCtrl.index == 1) {
                  _selectedDate = _selectedDate.add(const Duration(days: 7));
                } else {
                  _selectedDate = DateTime(
                    _selectedDate.year,
                    _selectedDate.month + 1,
                    _selectedDate.day,
                  );
                }
              });
              _load();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Health History'.tr(),
          style: const TextStyle(
            fontFamily: 'League Spartan',
            fontWeight: FontWeight.w900,
            color: _kTextDark,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _kPrimary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _kPrimary,
          tabs: _tabs.map((t) => Tab(text: t.tr())).toList(),
        ),
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          // Metric chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: _metrics.map((m) {
                final sel = m == _metric;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _metric = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _kPrimary.withOpacity(0.12) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? _kPrimary : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        m.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: sel ? _kPrimary : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: _kPrimary)),
            )
          else
            Expanded(
              child: RefreshIndicator(
                color: _kPrimary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  children: [
                    if (_records.isNotEmpty) ...[
                      Container(
                        height: 200,
                        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _buildChart(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_records.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            'No records for this period'.tr(),
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        ),
                      )
                    else
                      ..._buildGroupedCards(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    List<FlSpot> spots = [];
    for (int i = 0; i < _records.length; i++) {
      final r = _records[i];
      double? val;
      switch (_metric) {
        case 'Blood Pressure':
          final p = r.bloodPressure?.split('/');
          if (p != null && p.length == 2) val = double.tryParse(p[0].trim());
          break;
        case 'Heart Rate':
          val = r.heartRate?.toDouble();
          break;
        case 'Glucose':
          val = r.glucoseLevel;
          break;
        case 'Temperature':
          val = r.temperature;
          break;
      }
      if (val != null) spots.add(FlSpot(i.toDouble(), val));
    }
    if (spots.isEmpty) {
      return Center(
        child: Text(
          'No data'.tr(),
          style: TextStyle(color: Colors.grey.shade400),
        ),
      );
    }
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 5;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 5;
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade100, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= _records.length) {
                  return const SizedBox.shrink();
                }
                String label;
                if (_tabCtrl.index == 0) {
                  label = DateFormat('HH:mm').format(_records[i].recordedAt);
                } else if (_tabCtrl.index == 1)
                  label = DateFormat('EEE').format(_records[i].recordedAt);
                else
                  label = DateFormat('d').format(_records[i].recordedAt);
                return SideTitleWidget(
                  meta: m,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, m) => SideTitleWidget(
                meta: m,
                child: Text(
                  v.toStringAsFixed(0),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble().clamp(1, double.infinity),
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _kPrimary,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (sp, pct, bd, i) => FlDotCirclePainter(
                radius: 3,
                color: _kPrimary,
                strokeWidth: 0,
                strokeColor: Colors.transparent,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: _kPrimary.withOpacity(0.06),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedCards() {
    Map<String, List<HealthRecord>> grouped = {};
    for (final r in _records.reversed) {
      String d = DateFormat('d MMM yyyy').format(r.recordedAt);
      if (!grouped.containsKey(d)) grouped[d] = [];
      grouped[d]!.add(r);
    }
    return grouped.entries.map((e) => _buildGroupCard(e.key, e.value)).toList();
  }

  Widget _buildGroupCard(String dateStr, List<HealthRecord> records) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: _kTextDark,
            ),
          ),
          const Divider(height: 16),
          ...records.map((r) => _buildTimeRow(r)),
        ],
      ),
    );
  }

  Widget _buildTimeRow(HealthRecord r) {
    String val = '–';
    Color c = Colors.grey;
    IconData icon = Icons.circle;

    if (_metric == 'Blood Pressure') {
      val = r.bloodPressure?.isNotEmpty == true
          ? '${r.bloodPressure} mmHg'.tr()
          : '–';
      c = _bpStatus(r.bloodPressure).color;
      icon = Icons.show_chart;
    } else if (_metric == 'Heart Rate') {
      val = r.heartRate != null ? '${r.heartRate} bpm'.tr() : '–';
      c = _hrColor(r.heartRate);
      icon = Icons.favorite;
    } else if (_metric == 'Glucose') {
      val = r.glucoseLevel != null
          ? '${r.glucoseLevel!.toStringAsFixed(1)} mmol/L'.tr()
          : '–';
      c = _glucoseColor(r.glucoseLevel);
      icon = Icons.bloodtype;
    } else if (_metric == 'Temperature') {
      val = r.temperature != null
          ? '${r.temperature!.toStringAsFixed(1)} °C'.tr()
          : '–';
      c = _tempColor(r.temperature);
      icon = Icons.thermostat;
    }

    if (val == '–') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            DateFormat('h:mm a').format(r.recordedAt),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _kTextGrey,
            ),
          ),
          Row(
            children: [
              Text(
                val,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: c,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 20, color: c),
            ],
          ),
        ],
      ),
    );
  }
}
