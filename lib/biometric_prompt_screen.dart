import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'role_selection_screen.dart';
import 'elderly_dashboard.dart';

class BiometricPromptScreen extends StatefulWidget {
  const BiometricPromptScreen({super.key});

  @override
  State<BiometricPromptScreen> createState() => _BiometricPromptScreenState();
}

class _BiometricPromptScreenState extends State<BiometricPromptScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isSaving = false;

  Future<void> _enableBiometric() async {
    setState(() => _isSaving = true);
    try {
      // First check if any biometrics are enrolled on the device
      final List<BiometricType> availableBiometrics =
          await _localAuth.getAvailableBiometrics();

      if (availableBiometrics.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No biometrics enrolled. Please set up fingerprint or Face ID in your device settings first.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Try to authenticate to confirm biometric works
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Confirm your biometric to enable quick login',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('biometric_enabled', true);
        if (mounted) _goToDashboard();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Biometric setup failed: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', false);
    if (mounted) _goToDashboard();
  }

  Future<void> _goToDashboard() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    String? roleId;

    if (uid != null) {
      try {
        final res = await Supabase.instance.client
            .from('users')
            .select('role_id')
            .eq('user_id', uid)
            .maybeSingle();
        roleId = res?['role_id'] as String?;
      } catch (_) {}
    }

    if (!mounted) return;

    Widget destination;
    if (roleId == 'elderly') {
      destination = const ElderlyDashboard();
    } else if (roleId != null && roleId.isNotEmpty) {
      // Future caregiver dashboard
      destination = const RoleSelectionScreen();
    } else {
      // No role yet — go to onboarding
      destination = const RoleSelectionScreen();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),

              // Biometric Icon
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF55A47A).withOpacity(0.12),
                ),
                child: const Icon(
                  Icons.fingerprint,
                  size: 64,
                  color: Color(0xFF55A47A),
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'Enable Biometric\nLogin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF101113),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),

              // Subtitle
              const Text(
                'Use your fingerprint or Face ID to log in\nquickly and securely in the future.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6B7280),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 48),

              // Enable Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _enableBiometric,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF55A47A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Enable Biometric',
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Skip Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: _isSaving ? null : _skip,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Skip for Now',
                    style: TextStyle(
                      fontSize: 17,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Info note
              const Text(
                'You can change this setting later in your profile.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
