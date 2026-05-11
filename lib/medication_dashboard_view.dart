import 'package:flutter/material.dart';

class MedicationDashboardView extends StatelessWidget {
  const MedicationDashboardView({super.key});

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
          
          // Today Medicine
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today Medicine',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Monday, June 12',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Medicine Cards
          _buildMedicineCard(
            time: '08:30 AM',
            name: 'Metformin',
            description: 'Diabetes medicine\n2 tablets\nTake after meal',
            status: 'taken',
          ),
          _buildMedicineCard(
            time: '08:30 AM',
            name: 'Atorvastatin',
            description: 'Cholesterol medicine\n2 tablets\nTake after meal',
            status: 'pending',
          ),
          
          const SizedBox(height: 24),
          
          // Manage Button
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
                'Manage Medicine',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Medication Log Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Medication Log',
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
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildSegment('Yesterday', false)),
                  Expanded(child: _buildSegment('Today', true)),
                  Expanded(child: _buildSegment('Tomorrow', false)),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Missed Doses
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Missed Doses',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF5252),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildLogCard('Metformin', 'High', '11:00 PM', const Color(0xFFFFADAD)),
          _buildLogCard('Atorvastatin', 'Medium', '11:00 PM', const Color(0xFFFFD6A5)),
          _buildLogCard('Panadol', 'Low', '11:00 PM', const Color(0xFFFDFFB6)),
          
          const SizedBox(height: 24),
          
          // Taken Doses
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Taken Doses',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF51A77B),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildLogCard('Panadol', 'Low', '11:00 PM', const Color(0xFFFDFFB6)),
          
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildMedicineCard({
    required String time,
    required String name,
    required String description,
    required String status,
  }) {
    bool isTaken = status == 'taken';
    
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: Colors.black87),
              const SizedBox(width: 6),
              Text(
                time,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                    ),
                  ],
                ),
              ),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF8FB3B9), // Tealish placeholder background
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.medication, color: Colors.white, size: 40),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: isTaken ? const Color(0xFF51A77B) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: isTaken ? null : Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  isTaken ? 'I have taken' : 'Pending',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isTaken ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
              const Text(
                'Details >',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF51A77B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(String title, bool isSelected) {
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isSelected
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2, offset: const Offset(0, 1))]
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

  Widget _buildLogCard(String name, String priority, String time, Color bgColor) {
    Color priorityColor = priority == 'High' 
        ? Colors.red 
        : (priority == 'Medium' ? Colors.orange.shade800 : Colors.green.shade700);

    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text(
                    'Priority: ',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  Text(
                    priority,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: priorityColor),
                  ),
                ],
              ),
            ],
          ),
          Text(
            time,
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
