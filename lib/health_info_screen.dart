import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'caregiver_qr_screen.dart';
import 'package:easy_localization/easy_localization.dart';

class HealthInfoScreen extends StatefulWidget {
  final bool isEditMode;
  final String? elderlyId;
  
  const HealthInfoScreen({super.key, this.isEditMode = false, this.elderlyId});

  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  String? _bloodType;
  String? _allergies;
  String? _mobilityStatus;
  // Multi-select for chronic conditions
  final Set<String> _selectedConditions = {};
  // Multi-select for allergies
  final Set<String> _selectedAllergies = {};
  bool _isLoading = false;

  final TextEditingController _otherAllergyCtrl = TextEditingController();
  final TextEditingController _otherConditionCtrl = TextEditingController();

  final List<String> _bloodTypes = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'
  ];
  final List<String> _yesNo = ['Yes', 'No'];
  final List<String> _mobilityStatuses = [
    'Independent', 'Uses Cane', 'Uses Walker', 'Wheelchair Bound', 'Bedridden'
  ];
  final List<String> _chronicConditions = [
    'None', 'Cardiovascular', 'Diabetes', 'Hypertension',
    'Arthritis', 'Asthma', 'Kidney Disease', 'Other (Specify)'
  ];
  final List<String> _commonAllergies = [
    'Penicillin', 'Aspirin', 'Sulfa', 'Codeine', 'Peanuts', 'Seafood', 'Eggs', 'Milk', 'Other (Specify)'
  ];

  @override
  void dispose() {
    _otherAllergyCtrl.dispose();
    _otherConditionCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _loadExistingData();
    }
  }

  Future<void> _loadExistingData() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final targetId = widget.elderlyId ?? user.id;

      // Load basic health info
      final elderlyRes = await Supabase.instance.client
          .from('elderly')
          .select('blood_type, allergies, mobility_status, chronic_condition')
          .eq('user_id', targetId)
          .maybeSingle();

      if (elderlyRes != null) {
        _bloodType = elderlyRes['blood_type'];
        _allergies = elderlyRes['allergies'];
        _mobilityStatus = elderlyRes['mobility_status'];
        
        final chronic = elderlyRes['chronic_condition'] as String?;
        if (chronic != null && chronic.isNotEmpty) {
          if (chronic == 'None') {
            _selectedConditions.add('None');
          } else {
            final parts = chronic.split(',').map((e) => e.trim());
            for (final p in parts) {
              if (_chronicConditions.contains(p)) {
                _selectedConditions.add(p);
              } else {
                _selectedConditions.add('Other (Specify)');
                _otherConditionCtrl.text = _otherConditionCtrl.text.isEmpty ? p : '${_otherConditionCtrl.text}, $p';
              }
            }
          }
        }
      }

      // Load specific allergies if they exist
      if (_allergies == 'Yes') {
        final allergyRes = await Supabase.instance.client
            .from('allergy_list')
            .select('allergy(name)')
            .eq('elderly_id', targetId);
            
        final List list = allergyRes as List;
        for (var row in list) {
          final allergyData = row['allergy'];
          if (allergyData != null && allergyData['name'] != null) {
            final name = allergyData['name'] as String;
            if (_commonAllergies.contains(name)) {
              _selectedAllergies.add(name);
            } else {
              _selectedAllergies.add('Other (Specify)');
              _otherAllergyCtrl.text = _otherAllergyCtrl.text.isEmpty ? name : '${_otherAllergyCtrl.text}, $name';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading health info: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAndNext() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('[Auth] No authenticated user found');
      
      final targetId = widget.elderlyId ?? user.id;

      debugPrint('DEBUG: targetId = $targetId');

      // ── Step 1: Check if user exists in public.users ─────────────────────
      Map<String, dynamic>? existingUser;
      try {
        existingUser = await Supabase.instance.client
            .from('users')
            .select('user_id, role_id')
            .eq('user_id', targetId)
            .maybeSingle();
        debugPrint('DEBUG: existingUser = $existingUser');
      } catch (e) {
        throw Exception('[Step 1 - Read users] $e');
      }

      // ── Step 2: Create users row if missing ──────────────────────────────
      if (existingUser == null) {
        try {
          final insertData = <String, dynamic>{'user_id': targetId};
          if (targetId == user.id && user.email != null) insertData['email'] = user.email;
          if (targetId == user.id && user.phone != null && user.phone!.isNotEmpty) {
            insertData['phone_num'] = user.phone;
          }
          insertData['role_id'] = 'elderly';
          debugPrint('DEBUG: inserting into users: $insertData');
          await Supabase.instance.client.from('users').insert(insertData);
          debugPrint('DEBUG: users insert OK');
        } catch (e) {
          throw Exception('[Step 2 - Insert users] $e');
        }
      } else if (existingUser['role_id'] == null) {
        try {
          await Supabase.instance.client
              .from('users')
              .update({'role_id': 'elderly'})
              .eq('user_id', targetId);
          debugPrint('DEBUG: users role_id updated');
        } catch (e) {
          throw Exception('[Step 2 - Update role_id] $e');
        }
      }

      // ── Step 3: Build health data payload ───────────────────────────────
      final finalConditions = Set<String>.from(_selectedConditions);
      if (finalConditions.contains('Other (Specify)')) {
        finalConditions.remove('Other (Specify)');
        if (_otherConditionCtrl.text.trim().isNotEmpty) {
          finalConditions.addAll(_otherConditionCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
        }
      }
      
      final chronicStr = finalConditions.isEmpty
          ? null
          : finalConditions.contains('None')
              ? 'None'
              : finalConditions.join(', ');

      final data = <String, dynamic>{'user_id': targetId};
      if (_bloodType != null) data['blood_type'] = _bloodType;
      if (_allergies != null) data['allergies'] = _allergies;
      if (_mobilityStatus != null) data['mobility_status'] = _mobilityStatus;
      if (chronicStr != null) data['chronic_condition'] = chronicStr;
      debugPrint('DEBUG: elderly upsert data = $data');

      // ── Step 4: Upsert into elderly table ────────────────────────────────
      try {
        await Supabase.instance.client.from('elderly').upsert(
          data,
          onConflict: 'user_id',
        );
        debugPrint('DEBUG: elderly upsert OK');
      } catch (e) {
        throw Exception('[Step 4 - Upsert elderly] $e');
      }

      // ── Step 5: Save allergies to allergy_list ───────────────────────────
      if (_allergies == 'Yes' && (_selectedAllergies.isNotEmpty || _otherAllergyCtrl.text.isNotEmpty)) {
        try {
          // Clear old ones first to prevent duplicates (if updating)
          try { await Supabase.instance.client.from('allergy_list').delete().eq('elderly_id', targetId); } catch (_) {}

          final finalAllergies = Set<String>.from(_selectedAllergies);
          if (finalAllergies.contains('Other (Specify)')) {
            finalAllergies.remove('Other (Specify)');
            if (_otherAllergyCtrl.text.trim().isNotEmpty) {
              finalAllergies.addAll(_otherAllergyCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
            }
          }

          for (final allergyName in finalAllergies) {
            final checkRes = await Supabase.instance.client
                .from('allergy')
                .select('allergy_id')
                .eq('name', allergyName)
                .maybeSingle();

            String allergyId;
            if (checkRes == null) {
              final insRes = await Supabase.instance.client
                  .from('allergy')
                  .insert({'name': allergyName})
                  .select('allergy_id')
                  .single();
              allergyId = insRes['allergy_id'] as String;
            } else {
              allergyId = checkRes['allergy_id'] as String;
            }

            await Supabase.instance.client.from('allergy_list').upsert({
              'allergy_id': allergyId,
              'elderly_id': targetId,
            });
          }
          debugPrint('DEBUG: allergy_list upsert OK');
        } catch (e) {
          throw Exception('[Step 5 - Save allergies] $e');
        }
      } else if (_allergies == 'No') {
        try { await Supabase.instance.client.from('allergy_list').delete().eq('elderly_id', targetId); } catch (_) {}
      }

      if (mounted) {
        if (widget.isEditMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Health info updated successfully!'.tr()),
              backgroundColor: const Color(0xFF51A77B),
            ),
          );
          Navigator.pop(context);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CaregiverQrScreen()),
          );
        }
      }
    } catch (e) {
      debugPrint('ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Open Sans',
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
                        fontSize: 22,
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

  Widget _buildAllergySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Select your allergies'.tr(),
          style: TextStyle(
            fontFamily: 'Open Sans',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6C7278),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _commonAllergies.map((allergy) {
              final isSelected = _selectedAllergies.contains(allergy);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedAllergies.remove(allergy);
                    } else {
                      _selectedAllergies.add(allergy);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFE53935)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFE53935)
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    allergy,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF374151),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (_selectedAllergies.contains('Other (Specify)')) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _otherAllergyCtrl,
            decoration: InputDecoration(
              labelText: 'Please specify other allergies'.tr(),
              hintText: 'e.g. Pollen, Dust (comma separated)'.tr(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildChronicConditionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Chronic Condition'.tr(),
          style: TextStyle(
            fontFamily: 'Open Sans',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6C7278),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select all that apply'.tr(),
          style: TextStyle(
            fontFamily: 'Open Sans',
            fontSize: 12,
            color: Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _chronicConditions.map((condition) {
              final isSelected = _selectedConditions.contains(condition);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (condition == 'None') {
                      // Selecting "None" clears all other selections
                      _selectedConditions.clear();
                      _selectedConditions.add('None');
                    } else {
                      // Selecting any other condition removes "None"
                      _selectedConditions.remove('None');
                      if (isSelected) {
                        _selectedConditions.remove(condition);
                      } else {
                        _selectedConditions.add(condition);
                      }
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF51A77B)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF51A77B)
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    condition,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF374151),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (_selectedConditions.contains('Other (Specify)')) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _otherConditionCtrl,
            decoration: InputDecoration(
              labelText: 'Please specify other conditions'.tr(),
              hintText: 'e.g. Asthma, Thyroid (comma separated)'.tr(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
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
            ? Center(child: CircularProgressIndicator(color: Color(0xFF51A77B)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Column(
                  children: [
                    Text(
                      widget.isEditMode ? 'Edit Health Info'.tr() : 'Health Info'.tr(),
                      style: TextStyle(
                        fontFamily: 'League Spartan',
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF27252E),
                        letterSpacing: 1.08,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isEditMode 
                          ? 'Update your health information below'.tr()
                          : 'Select your basic health information for better experience'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Open Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27252E),
                        letterSpacing: 0.36,
                      ),
                    ),
                    const SizedBox(height: 40),

                    _buildDropdown(
                      'Blood Type', _bloodType, _bloodTypes,
                      (v) => setState(() => _bloodType = v),
                    ),
                    _buildDropdown(
                      'Allergies', _allergies, _yesNo,
                      (v) => setState(() {
                        _allergies = v;
                        if (v == 'No') _selectedAllergies.clear();
                      }),
                    ),
                    if (_allergies == 'Yes') _buildAllergySelector(),
                    _buildDropdown(
                      'Mobility Status', _mobilityStatus, _mobilityStatuses,
                      (v) => setState(() => _mobilityStatus = v),
                    ),
                    // Multi-select chip picker for chronic conditions
                    _buildChronicConditionSelector(),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saveAndNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF51A77B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          widget.isEditMode ? 'Update Info'.tr() : 'Save & Continue'.tr(),
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (!widget.isEditMode) ...[
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CaregiverQrScreen()),
                          );
                        },
                        child: Text(
                          'Skip for now'.tr(),
                          style: TextStyle(
                            color: Color(0xFF51A77B),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}
