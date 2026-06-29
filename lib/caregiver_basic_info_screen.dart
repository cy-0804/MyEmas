import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'caregiver_dashboard.dart';
import 'role_selection_screen.dart';
import 'profile_success_screen.dart';
import 'package:easy_localization/easy_localization.dart';

class CaregiverBasicInfoScreen extends StatefulWidget {
  const CaregiverBasicInfoScreen({super.key});

  @override
  State<CaregiverBasicInfoScreen> createState() =>
      _CaregiverBasicInfoScreenState();
}

class _CaregiverBasicInfoScreenState extends State<CaregiverBasicInfoScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedGender;
  bool _isLoading = true;

  // ─── colour tokens ─────────────────────────────────────────────────────────
  static const _kBlue = Color(0xFF00539E);
  static const _kGreen = Color(0xFF51A77B);

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final userData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();

        if (userData != null && mounted) {
          setState(() {
            _nameController.text = userData['fullname'] ?? '';
            _phoneController.text =
                userData['phone_num']?.replaceAll('+60', '') ?? '';
            _emailController.text = userData['email'] ?? '';
            _selectedGender = userData['gender'];
            if (userData['date_of_birth'] != null) {
              _selectedDate = DateTime.tryParse(userData['date_of_birth']);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(1980),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveAndFinish() async {
    if (_selectedDate == null || _selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select Birth Date and Gender'.tr())),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      // Save basic info
      final updateData = <String, dynamic>{
        if (_nameController.text.isNotEmpty) 'fullname': _nameController.text,
        if (_phoneController.text.isNotEmpty)
          'phone_num': '+60${_phoneController.text}',
        if (_emailController.text.isNotEmpty) 'email': _emailController.text,
        'date_of_birth': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'gender': _selectedGender,
      };

      await Supabase.instance.client
          .from('users')
          .update(updateData)
          .eq('user_id', user.id);

      // Ensure caregiver row exists
      final caregiverRow = await Supabase.instance.client
          .from('caregiver')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (caregiverRow == null) {
        await Supabase.instance.client.from('caregiver').insert({
          'user_id': user.id,
        });
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const ProfileSuccessScreen(nextScreen: CaregiverDashboard()),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 16.0),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Open Sans',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6C7278),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboardType,
    Widget? prefix,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: prefix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBlue, width: 1.5),
        ),
      ),
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
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
              );
            }
          },
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: _kBlue))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 12.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with caregiver badge
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _kBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.health_and_safety_outlined,
                                  size: 16,
                                  color: _kBlue,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Caregiver Setup'.tr(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _kBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Basic Info'.tr(),
                            style: TextStyle(
                              fontFamily: 'League Spartan',
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF27252E),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Tell us about yourself so patients can identify you'
                                .tr(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Open Sans',
                              fontSize: 14,
                              color: Color(0xFF6C7278),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24),

                    _buildLabel('Full Name'),
                    _buildTextField(
                      _nameController,
                      'Enter your full name',
                      prefix: Icon(
                        Icons.person_outline,
                        color: Colors.grey.shade400,
                      ),
                    ),

                    _buildLabel('Phone Number'),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Enter your phone number'.tr(),
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '+60'.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: _kBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),

                    _buildLabel('Email'),
                    _buildTextField(
                      _emailController,
                      'Enter your email address',
                      keyboardType: TextInputType.emailAddress,
                      prefix: Icon(
                        Icons.mail_outline,
                        color: Colors.grey.shade400,
                      ),
                    ),

                    _buildLabel('Birth Date'),
                    GestureDetector(
                      onTap: () => _selectDate(context),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedDate == null
                                  ? 'YYYY/MM/DD'
                                  : DateFormat(
                                      'yyyy/MM/dd',
                                    ).format(_selectedDate!),
                              style: TextStyle(
                                color: _selectedDate == null
                                    ? Colors.grey.shade400
                                    : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                            Icon(
                              Icons.calendar_today_outlined,
                              color: Colors.grey.shade600,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    _buildLabel('Gender'),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedGender = 'MALE'),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _selectedGender == 'MALE'
                                    ? _kBlue.withOpacity(0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: _selectedGender == 'MALE'
                                    ? Border.all(color: _kBlue)
                                    : Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'MALE'.tr(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _selectedGender == 'MALE'
                                      ? _kBlue
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedGender = 'FEMALE'),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _selectedGender == 'FEMALE'
                                    ? const Color(0xFFFFD3DD).withOpacity(0.4)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: _selectedGender == 'FEMALE'
                                    ? Border.all(color: Colors.pinkAccent)
                                    : Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'FEMALE'.tr(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _selectedGender == 'FEMALE'
                                      ? Colors.pinkAccent
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saveAndFinish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Get Started'.tr(),
                          style: TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}
