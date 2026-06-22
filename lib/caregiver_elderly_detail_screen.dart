import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'caregiver_dashboard.dart';
import 'medication_dashboard_view.dart';
import 'schedule_dashboard_view.dart';
import 'ai_health_service.dart';

// ─── colour tokens ────────────────────────────────────────────────────────────
const _kBlue  = Color(0xFF00539E);
const _kGreen = Color(0xFF51A77B);
const _kDark  = Color(0xFF1A1D2E);
const _kGrey  = Color(0xFF6C7278);
const _kBg    = Color(0xFFF0F4F8);

// ─── Health risk helper ───────────────────────────────────────────────────────
({String label, Color color, Color bg}) _riskStyle(String? level) {
  switch (level) {
    case 'high':   return (label: 'HIGH RISK',   color: const Color(0xFFD32F2F), bg: const Color(0xFFFFEBEE));
    case 'medium': return (label: 'MEDIUM RISK', color: const Color(0xFFF57C00), bg: const Color(0xFFFFF3E0));
    default:       return (label: 'LOW RISK',    color: const Color(0xFF388E3C), bg: const Color(0xFFE8F5E9));
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────
class _HealthRecordDetail {
  final String id;
  final String? bloodPressure;
  final int? heartRate;
  final double? glucoseLevel;
  final double? temperature;
  final String? mood;
  final DateTime recordedAt;
  final String? riskLevel;
  final String? recommendation;

  const _HealthRecordDetail({
    required this.id,
    this.bloodPressure,
    this.heartRate,
    this.glucoseLevel,
    this.temperature,
    this.mood,
    required this.recordedAt,
    this.riskLevel,
    this.recommendation,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// CaregiverElderlyDetailScreen
// ═════════════════════════════════════════════════════════════════════════════
class CaregiverElderlyDetailScreen extends StatefulWidget {
  final LinkedElderly elderly;
  const CaregiverElderlyDetailScreen({super.key, required this.elderly});

  @override
  State<CaregiverElderlyDetailScreen> createState() => _CaregiverElderlyDetailScreenState();
}

class _CaregiverElderlyDetailScreenState extends State<CaregiverElderlyDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<_HealthRecordDetail> _records = [];
  bool _loading = true;

  // AI Summary State
  String _aiTimeframe = 'week';
  bool _generatingAi = false;
  String? _aiSummary;
  String _filterMetric = 'Blood Pressure';
  static const _metrics = ['Blood Pressure', 'Heart Rate', 'Glucose', 'Temperature'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _loadRecords();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;

      // Load last 30 days of health records
      final start = DateTime.now().subtract(const Duration(days: 30));
      final res = await db
          .from('health_record')
          .select('record_id, blood_pressure, heart_rate, glucose_level, temperature, recorded_at')
          .eq('elderly_id', widget.elderly.elderlyId)
          .gte('recorded_at', start.toUtc().toIso8601String())
          .order('recorded_at', ascending: false);

      final List<_HealthRecordDetail> details = [];
      for (final r in (res as List)) {
        final rid = r['record_id'] as String;
        // Load risk
        final riskRow = await db
            .from('health_risk_assessment')
            .select('risk_level, recommendation')
            .eq('record_id', rid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        details.add(_HealthRecordDetail(
          id: rid,
          bloodPressure: r['blood_pressure'] as String?,
          heartRate: r['heart_rate'] as int?,
          glucoseLevel: (r['glucose_level'] as num?)?.toDouble(),
          temperature: (r['temperature'] as num?)?.toDouble(),
          mood: null, // Removed from DB query
          recordedAt: DateTime.parse(r['recorded_at'] as String).toLocal(),
          riskLevel: riskRow?['risk_level'] as String?,
          recommendation: riskRow?['recommendation'] as String?,
        ));
      }

      if (mounted) setState(() { _records = details; _loading = false; });
    } catch (e) {
      debugPrint('Detail load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateAiSummary() async {
    setState(() => _generatingAi = true);
    final summary = await AiHealthService.generateSummary(
      elderlyId: widget.elderly.elderlyId,
      timeframe: _aiTimeframe,
    );
    if (mounted) {
      setState(() {
        _aiSummary = summary;
        _generatingAi = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final el = widget.elderly;
    final ri = _riskStyle(el.latestRisk);

    return Scaffold(
      backgroundColor: _kBg,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_2, color: Colors.white),
                tooltip: 'Share QR Code',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text('Patient QR Code', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'League Spartan', color: Color(0xFF27252E))),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Share this with another caregiver to give them access to monitor ${el.name}.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                            child: SizedBox(
                              width: 200,
                              height: 200,
                              child: QrImageView(
                                data: el.elderlyId,
                                version: QrVersions.auto,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(fontSize: 16, color: _kBlue))),
                      ],
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.link_off, color: Colors.white),
                tooltip: 'Unlink Patient',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Unlink Patient?'),
                      content: Text('Are you sure you want to stop monitoring ${el.name}? You will no longer have access to their health data.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Unlink'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    try {
                      final db = Supabase.instance.client;
                      final uid = db.auth.currentUser?.id;
                      if (uid != null) {
                        await db.from('care_link').delete()
                            .eq('caregiver_id', uid)
                            .eq('elderly_id', el.elderlyId);
                        if (mounted) {
                          Navigator.pop(context, true);
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00539E), Color(0xFF003366)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                // kToolbarHeight (56) + tabs (48) + status bar
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 60, // clear the TabBar at the bottom
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            child: Text(
                              el.name.isNotEmpty ? el.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(el.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'League Spartan')),
                              const SizedBox(height: 4),
                              if (el.gender != null) Text(el.gender!.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1)),
                              if (el.chronicCondition != null && el.chronicCondition!.isNotEmpty)
                                Text(el.chronicCondition!, style: const TextStyle(color: Colors.white60, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: ri.color.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10)),
                            child: Text(ri.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabCtrl,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [Tab(text: 'Overview'), Tab(text: 'History'), Tab(text: 'Info'), Tab(text: 'Meds'), Tab(text: 'Schedule')],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildOverviewTab(),
            _buildHistoryTab(),
            _buildInfoTab(),
            MedicationDashboardView(elderlyId: el.elderlyId),
            ScheduleDashboardView(elderlyId: el.elderlyId),
          ],
        ),
      ),
    );
  }

  // ─── Overview Tab ────────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final latest = _records.isNotEmpty ? _records.first : null;

    return RefreshIndicator(
      color: _kBlue,
      onRefresh: _loadRecords,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Latest vitals
          _sectionTitle('Latest Vitals'),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: _kBlue))
          else if (latest == null)
            _noDataCard('No health records available')
          else ...[
            _buildVitalCard('Blood Pressure', latest.bloodPressure ?? '–', 'mmHg', Icons.show_chart, Colors.blue.shade600, Colors.blue.shade50),
            _buildVitalCard('Heart Rate', latest.heartRate != null ? '${latest.heartRate}' : '–', 'bpm', Icons.favorite_border, Colors.red.shade400, Colors.red.shade50),
            _buildVitalCard('Glucose Level', latest.glucoseLevel?.toStringAsFixed(1) ?? '–', 'mmol/L', Icons.bloodtype, Colors.green.shade600, Colors.green.shade50),
            _buildVitalCard('Temperature', latest.temperature?.toStringAsFixed(1) ?? '–', '°C', Icons.thermostat, Colors.orange.shade600, Colors.orange.shade50),
            const SizedBox(height: 4),
            Center(child: Text('Recorded: ${DateFormat('MMM d, h:mm a').format(latest.recordedAt)}', style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
          ],

          const SizedBox(height: 24),

          // Risk Assessment
          _sectionTitle('Current Risk Status'),
          const SizedBox(height: 12),
          if (latest != null) ...[
            _buildRiskCard(latest),
          ] else
            _noDataCard('Add health records to see risk status'),

          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Widget _buildVitalCard(String title, String value, String unit, IconData icon, Color iconColor, Color iconBg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, color: _kGrey, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _kDark)),
              const SizedBox(width: 4),
              Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(unit, style: TextStyle(fontSize: 14, color: Colors.grey.shade500))),
            ]),
          ]),
        ],
      ),
    );
  }

  Widget _buildRiskCard(_HealthRecordDetail r) {
    final ri = _riskStyle(r.riskLevel);
    if (r.riskLevel == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Icon(Icons.help_outline, color: Colors.grey.shade400, size: 24),
          const SizedBox(width: 12),
          const Text('No risk assessment yet', style: TextStyle(color: _kGrey, fontSize: 15)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ri.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ri.color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r.riskLevel == 'high' ? Icons.warning_amber_rounded : r.riskLevel == 'medium' ? Icons.info_outline : Icons.check_circle_outline,
              color: ri.color, size: 24),
          const SizedBox(width: 8),
          Text(ri.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ri.color)),
        ]),
        if (r.recommendation != null && r.recommendation!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(r.recommendation!, style: TextStyle(fontSize: 14, color: ri.color.withValues(alpha: 0.8))),
          const SizedBox(height: 8),
          Text('Disclaimer: AI-generated risk assessment. Consult a doctor for medical advice.', style: TextStyle(fontSize: 10, color: ri.color.withValues(alpha: 0.6), fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }


  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          // ─── AI Health Insights Section ───
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.purple.shade100, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('AI Health Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark))),
                    DropdownButton<String>(
                      value: _aiTimeframe,
                      underline: const SizedBox.shrink(),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                      style: const TextStyle(fontSize: 13, color: _kBlue, fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: 'day', child: Text('Today')),
                        DropdownMenuItem(value: 'week', child: Text('Past 7 Days')),
                        DropdownMenuItem(value: 'month', child: Text('Past 30 Days')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _aiTimeframe = val;
                            _aiSummary = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_generatingAi)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: Colors.purple),
                          SizedBox(height: 12),
                          Text('AI is analyzing records...', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                else if (_aiSummary != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownBody(data: _aiSummary!),
                      const SizedBox(height: 12),
                      const Text('Disclaimer: This is an AI-generated summary and should not replace professional medical advice.', style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generateAiSummary,
                      icon: const Icon(Icons.analytics_outlined, size: 18),
                      label: const Text('Generate Summary'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade50,
                        foregroundColor: Colors.purple,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Metric filter
        Container(
          height: 48,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: _metrics.map((m) {
                final sel = m == _filterMetric;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterMetric = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? _kBlue : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(m, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: sel ? Colors.white : Colors.black87)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Chart
        if (_records.isNotEmpty)
          Container(
            height: 180,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
            child: _buildChart(),
          ),
        // List
        if (_loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: _kBlue)))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            itemCount: _records.length,
            itemBuilder: (_, i) => _buildRecordRow(_records[i]),
          ),
      ],
    ),
  );
}

  Widget _buildChart() {
    final spots = <FlSpot>[];
    final relevant = _records.reversed.toList();
    for (int i = 0; i < relevant.length && i < 10; i++) {
      final r = relevant[i];
      double? val;
      switch (_filterMetric) {
        case 'Blood Pressure':
          final p = r.bloodPressure?.split('/');
          if (p != null && p.length == 2) val = double.tryParse(p[0].trim());
          break;
        case 'Heart Rate':   val = r.heartRate?.toDouble(); break;
        case 'Glucose':      val = r.glucoseLevel; break;
        case 'Temperature':  val = r.temperature; break;
      }
      if (val != null) spots.add(FlSpot(i.toDouble(), val));
    }

    if (spots.isEmpty) return Center(child: Text('No data', style: TextStyle(color: Colors.grey.shade400)));

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 3;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 3;

    return LineChart(LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade100, strokeWidth: 1)),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20, interval: 1,
          getTitlesWidget: (v, m) {
            final idx = v.toInt();
            final rev = _records.reversed.toList();
            if (idx < 0 || idx >= rev.length) return const SizedBox.shrink();
            return SideTitleWidget(meta: m, child: Text(DateFormat('M/d').format(rev[idx].recordedAt), style: TextStyle(fontSize: 9, color: Colors.grey.shade500)));
          })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: (maxY - minY) / 3,
          getTitlesWidget: (v, m) => SideTitleWidget(meta: m, child: Text(v.toStringAsFixed(0), style: TextStyle(fontSize: 9, color: Colors.grey.shade500))))),
      ),
      borderData: FlBorderData(show: false),
      minX: 0, maxX: (spots.length - 1).toDouble().clamp(1, 9),
      minY: minY, maxY: maxY,
      lineBarsData: [LineChartBarData(
        spots: spots, isCurved: true, color: _kBlue, barWidth: 2, isStrokeCapRound: true,
        dotData: FlDotData(show: true, getDotPainter: (sp, _, __, ___) => FlDotCirclePainter(radius: 3, color: _kBlue, strokeWidth: 0, strokeColor: Colors.transparent)),
        belowBarData: BarAreaData(show: true, color: _kBlue.withValues(alpha: 0.06)),
      )],
    ));
  }

  Widget _buildRecordRow(_HealthRecordDetail r) {
    final ri = _riskStyle(r.riskLevel);
    String val = '', unit = '';
    switch (_filterMetric) {
      case 'Blood Pressure': val = r.bloodPressure ?? '–'; unit = 'mmHg'; break;
      case 'Heart Rate': val = r.heartRate != null ? '${r.heartRate}' : '–'; unit = 'bpm'; break;
      case 'Glucose': val = r.glucoseLevel?.toStringAsFixed(1) ?? '–'; unit = 'mmol/L'; break;
      case 'Temperature': val = r.temperature?.toStringAsFixed(1) ?? '–'; unit = '°C'; break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(DateFormat('MMM d, h:mm a').format(r.recordedAt), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _kDark)),
          if (r.riskLevel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: ri.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: ri.color.withValues(alpha: 0.3))),
              child: Text(ri.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ri.color)),
            ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(val, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(width: 4),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(unit, style: TextStyle(fontSize: 14, color: Colors.grey.shade500))),
        ]),
        if (r.recommendation != null && r.recommendation!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(r.recommendation!, style: TextStyle(fontSize: 12, color: ri.color), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }

  // ─── Info Tab ─────────────────────────────────────────────────────────────
  Widget _buildInfoTab() {
    final el = widget.elderly;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Personal Information'),
        const SizedBox(height: 12),
        _infoCard([
          _infoRow(Icons.person_outline, 'Full Name', el.name),
          if (el.gender != null) _infoRow(Icons.wc, 'Gender', el.gender!),
          if (el.email != null) _infoRow(Icons.mail_outline, 'Email', el.email!),
          if (el.phone != null) _infoRow(Icons.phone_outlined, 'Phone', el.phone!),
        ]),

        const SizedBox(height: 20),
        _sectionTitle('Medical Information'),
        const SizedBox(height: 12),
        _infoCard([
          _infoRow(Icons.bloodtype, 'Blood Type', el.bloodType ?? 'Not specified'),
          _infoRow(Icons.healing_outlined, 'Chronic Condition', el.chronicCondition ?? 'None'),
        ]),

        const SizedBox(height: 20),
        _sectionTitle('Health Summary (30 days)'),
        const SizedBox(height: 12),
        _buildStatsCard(),

        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _buildStatsCard() {
    final totalRecords = _records.length;
    final highRisk   = _records.where((r) => r.riskLevel == 'high').length;
    final medRisk    = _records.where((r) => r.riskLevel == 'medium').length;
    final lowRisk    = _records.where((r) => r.riskLevel == 'low').length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Row(children: [
          _statBox('Total Records', '$totalRecords', _kBlue),
          const SizedBox(width: 12),
          _statBox('High Risk', '$highRisk', const Color(0xFFD32F2F)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _statBox('Medium Risk', '$medRisk', const Color(0xFFF57C00)),
          const SizedBox(width: 12),
          _statBox('Low Risk', '$lowRisk', const Color(0xFF388E3C)),
        ]),
      ]),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  Widget _infoCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: children),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Row(children: [
        Icon(icon, size: 18, color: _kGrey),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _kGrey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _kDark)),
        ]),
      ]),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontFamily: 'League Spartan', fontSize: 18, fontWeight: FontWeight.bold, color: _kDark));
  }

  Widget _noDataCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Icon(Icons.monitor_heart_outlined, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(fontSize: 16, color: Colors.grey.shade500), textAlign: TextAlign.center),
      ]),
    );
  }
}
