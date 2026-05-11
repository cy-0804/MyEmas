import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'caregiver_qr_screen.dart';

class HealthInfoScreen extends StatefulWidget {
  const HealthInfoScreen({super.key});

  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  String? _bloodType;
  String? _allergies;
  String? _mobilityStatus;
  String? _chronicCondition;
  bool _isLoading = false;

  final List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'];
  final List<String> _yesNo = ['Yes', 'No'];
  final List<String> _mobilityStatuses = ['Independent', 'Uses Cane', 'Uses Walker', 'Wheelchair Bound', 'Bedridden'];
  final List<String> _chronicConditions = ['None', 'Cardiovascular', 'Diabetes', 'Hypertension', 'Arthritis', 'Asthma', 'Other'];

  Future<void> _saveAndNext() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      // Ensure a record exists in `elderly` table
      final existingRecord = await Supabase.instance.client
          .from('elderly')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      final data = {
        'blood_type': _bloodType,
        'allergies': _allergies,
        'mobility_status': _mobilityStatus,
        'chronic_condition': _chronicCondition,
      };
      
      data.removeWhere((key, value) => value == null);

      if (existingRecord == null) {
        data['user_id'] = user.id;
        await Supabase.instance.client.from('elderly').insert(data);
      } else {
        if (data.isNotEmpty) {
          await Supabase.instance.client.from('elderly').update(data).eq('user_id', user.id);
        }
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CaregiverQrScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildDropdown(String label, String? value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6C7278),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 57,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down),
              alignment: Alignment.center,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Center(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27252E),
                      ),
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF51A77B)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Column(
                  children: [
                    const Text(
                      'Health Info',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF27252E),
                        letterSpacing: 1.08,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select your basic health information for better experience',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27252E),
                        letterSpacing: 0.36,
                      ),
                    ),
                    const SizedBox(height: 40),

                    _buildDropdown('Blood Type', _bloodType, _bloodTypes, (v) => setState(() => _bloodType = v)),
                    _buildDropdown('Allergies', _allergies, _yesNo, (v) => setState(() => _allergies = v)),
                    _buildDropdown('Mobility Status', _mobilityStatus, _mobilityStatuses, (v) => setState(() => _mobilityStatus = v)),
                    _buildDropdown('Chronic Condition', _chronicCondition, _chronicConditions, (v) => setState(() => _chronicCondition = v)),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saveAndNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF51A77B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save & Continue',
                          style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CaregiverQrScreen()),
                        );
                      },
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          color: Color(0xFF51A77B),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}
