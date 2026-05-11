import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class HealthDashboardView extends StatelessWidget {
  const HealthDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Search Bar
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFCFC),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Search',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Icon(Icons.mic, color: Colors.grey.shade600),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Today Health
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Today Health',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF51A77B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildHealthCard(
                    title: 'Heart Rate',
                    value: '65',
                    unit: 'bpm',
                    icon: Icons.favorite,
                    iconColor: Colors.red.shade300,
                    iconBgColor: Colors.red.shade50,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildHealthCard(
                    title: 'Blood Pressure',
                    value: '120/79',
                    unit: 'mmHg',
                    icon: Icons.show_chart,
                    iconColor: Colors.blue.shade400,
                    iconBgColor: Colors.blue.shade50,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildHealthCard(
                    title: 'Glucose Level',
                    value: '79',
                    unit: 'mmol/L',
                    icon: Icons.bloodtype,
                    iconColor: Colors.green.shade400,
                    iconBgColor: Colors.green.shade50,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildHealthCard(
                    title: 'Temperature',
                    value: '35',
                    unit: '°C',
                    icon: Icons.thermostat,
                    iconColor: Colors.grey.shade600,
                    iconBgColor: Colors.grey.shade200,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Latest Update
          Center(
            child: Text(
              'Latest Update: 9:00 AM',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF51A77B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 0,
              ),
              child: const Text(
                'Add New Record',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Health History
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Health History',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF51A77B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Segmented Control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildSegment('Day', true)),
                  Expanded(child: _buildSegment('Week', false)),
                  Expanded(child: _buildSegment('Month', false)),
                  Expanded(child: _buildSegment('Year', false)),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildFilterChip('Heart Rate', false),
                const SizedBox(width: 8),
                _buildFilterChip('Blood Pressure', true),
                const SizedBox(width: 8),
                _buildFilterChip('Glucose Level', false),
                const SizedBox(width: 8),
                _buildFilterChip('Temperature', false),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Chart
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 220,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _buildChart(),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // History Records
          _buildRecordCard('Oct 24, 08:30 AM', '122/82', 'Normal', Colors.green),
          _buildRecordCard('Oct 24, 1:00 PM', '138/88', 'Elevated', Colors.orange),
          _buildRecordCard('Oct 24, 8:00 PM', '122/82', 'Normal', Colors.green),
          
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildHealthCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(unit, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(String title, bool isSelected) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isSelected
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
            : [],
      ),
      alignment: Alignment.center,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          color: isSelected ? Colors.black : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildFilterChip(String title, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.blue.shade700 : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildRecordCard(String date, String value, String status, MaterialColor statusColor) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BLOOD PRESSURE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
                      const SizedBox(width: 4),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('mmHg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.shade300),
                ),
                child: Text(
                  status,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor.shade600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 6,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.grey.shade200, strokeWidth: 1);
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                const style = TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 10);
                Widget text;
                switch (value.toInt()) {
                  case 0: text = const Text('Mon', style: style); break;
                  case 1: text = const Text('Tue', style: style); break;
                  case 2: text = const Text('Wed', style: style); break;
                  case 3: text = const Text('Thu', style: style); break;
                  case 4: text = const Text('Fri', style: style); break;
                  case 5: text = const Text('Sat', style: style); break;
                  case 6: text = const Text('Sun', style: style); break;
                  default: text = const Text('', style: style); break;
                }
                return SideTitleWidget(meta: meta, child: text);
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                Widget text = const Text('');
                if (value == 113 || value == 125 || value == 131 || value == 139) {
                  text = Text(value.toInt().toString(), style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.bold));
                }
                return SideTitleWidget(meta: meta, child: text);
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 6,
        minY: 105,
        maxY: 145,
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 115),
              FlSpot(1, 126),
              FlSpot(2, 118),
              FlSpot(3, 128),
              FlSpot(4, 123),
              FlSpot(5, 134),
              FlSpot(6, 125),
            ],
            isCurved: true,
            color: Colors.blue.shade400,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: Colors.blue.shade200,
                strokeWidth: 2,
                strokeColor: Colors.blue.shade400,
              ),
            ),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }
}
