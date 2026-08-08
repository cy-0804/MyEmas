import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'basic_info_screen.dart';
import 'caregiver_basic_info_screen.dart';
import 'login_screen.dart';
import 'package:easy_localization/easy_localization.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;

  Future<void> _selectRole(String role) async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No authenticated user found');
      
      final existingUser = await Supabase.instance.client
          .from('users')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingUser == null) {
        final insertData = {'user_id': user.id, 'role_id': role};
        if (user.email != null) insertData['email'] = user.email!;
        try {
          await Supabase.instance.client.from('users').insert(insertData);
        } catch (e) {
          if (e.toString().contains('users_email_key')) {
            insertData.remove('email');
            await Supabase.instance.client.from('users').insert(insertData);
          } else {
            rethrow;
          }
        }
      } else {
        await Supabase.instance.client
            .from('users')
            .update({'role_id': role})
            .eq('user_id', user.id);
      }

      if (mounted) {
        if (role == 'caregiver') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CaregiverBasicInfoScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BasicInfoScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildRoleCard({
    required String title,
    required String description,
    required Color titleColor,
    required String image1,
    required String image2,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 325,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color.fromRGBO(108, 114, 120, 0.36)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20.0, bottom: 9.0),
              child: Column(
                children: [
                  // Images row
                  SizedBox(
                    height: 158,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(child: Image.asset(image1, fit: BoxFit.contain)),
                        const SizedBox(width: 8),
                        Expanded(child: Image.asset(image2, fit: BoxFit.contain)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'League Spartan',
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                      height: 1.4,
                    ),
                  ),
                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Open Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF47494A),
                        height: 1.37,
                        letterSpacing: 1.12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onTap == null)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Coming Soon'.tr(), style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
          ],
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
          onPressed: () async {
            await Supabase.instance.client.auth.signOut();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          },
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF51A77B)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Select Your Role'.tr(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF27252E),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 60),
                    _buildRoleCard(
                      title: 'Elderly'.tr(),
                      description: 'Simple interface, voice commands, and health tracking tools.',
                      titleColor: const Color(0xFF3F8863),
                      image1: 'assets/senior.png',
                      image2: 'assets/senior (1).png',
                      onTap: () => _selectRole('elderly'),
                    ),
                    const SizedBox(height: 30),
                    _buildRoleCard(
                      title: 'Caregiver'.tr(),
                      description: 'Remote monitoring, alert management, and caregiver support.',
                      titleColor: const Color(0xFF00539E),
                      image1: 'assets/caregiver.png',
                      image2: 'assets/caregiver (1).png',
                      onTap: () => _selectRole('caregiver'),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}
