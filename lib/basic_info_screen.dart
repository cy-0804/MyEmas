import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'health_info_intro_screen.dart';
import 'role_selection_screen.dart';
import 'package:easy_localization/easy_localization.dart';

class BasicInfoScreen extends StatefulWidget {
  const BasicInfoScreen({super.key});

  @override
  State<BasicInfoScreen> createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends State<BasicInfoScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedGender;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
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
      debugPrint("Error loading data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(1960),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF51A77B),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveAndNext() async {
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

      final updateData = {
        'fullname': _nameController.text.isNotEmpty
            ? _nameController.text
            : null,
        'phone_num': _phoneController.text.isNotEmpty
            ? '+60${_phoneController.text}'
            : null,
        'email': _emailController.text.isNotEmpty
            ? _emailController.text
            : null,
        'date_of_birth': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'gender': _selectedGender,
      };

      updateData.removeWhere((key, value) => value == null);

      await Supabase.instance.client
          .from('users')
          .update(updateData)
          .eq('user_id', user.id);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HealthInfoIntroScreen()),
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
            ? Center(child: CircularProgressIndicator(color: Color(0xFF51A77B)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 12.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Basic Info'.tr(),
                        style: TextStyle(
                          fontFamily: 'League Spartan',
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF27252E),
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Select your basic info...'.tr(),
                        style: TextStyle(
                          fontFamily: 'Open Sans',
                          fontSize: 16,
                          color: Color(0xFF47494A),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),

                    _buildLabel('Full Name'),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Enter your full name'.tr(),
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: Colors.grey.shade400,
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
                      ),
                    ),

                    _buildLabel('Email'),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Enter your email address'.tr(),
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.mail_outline,
                          color: Colors.grey.shade400,
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
                                    ? const Color(
                                        0xFFC1E2FF,
                                      ).withValues(alpha: 0.47)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: _selectedGender == 'MALE'
                                    ? null
                                    : Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'MALE'.tr(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _selectedGender == 'MALE'
                                      ? Colors.black
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
                                    ? const Color(
                                        0xFFFFD3DD,
                                      ).withValues(alpha: 0.41)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: _selectedGender == 'FEMALE'
                                    ? null
                                    : Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'FEMALE'.tr(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _selectedGender == 'FEMALE'
                                      ? Colors.black
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
                        onPressed: _saveAndNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF51A77B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Next'.tr(),
                          style: TextStyle(
                            fontSize: 24,
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
