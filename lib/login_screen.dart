import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sign_up_screen.dart';
import 'role_selection_screen.dart';
import 'elderly_dashboard.dart';
import 'biometric_prompt_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  final TextEditingController _emailPhoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      bool canCheck = false;
      bool isAvailable = false;
      try {
        canCheck = await _localAuth.canCheckBiometrics;
        isAvailable = await _localAuth.isDeviceSupported();
      } catch (_) {
        // Device does not support biometrics
      }

      if (mounted) {
        setState(() {
          _biometricAvailable = canCheck || isAvailable;
          _biometricEnabled = biometricEnabled;
        });
      }

      // Auto-trigger biometric login if enabled and available
      if (biometricEnabled && (canCheck || isAvailable)) {
        await _loginWithBiometric();
      }
    } catch (_) {
      // Biometrics not available on this device
    }
  }

  Future<void> _loginWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to log in to MyEmas',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (authenticated && mounted) {
        await _navigateAfterLogin();
      }
    } catch (e) {
      // Biometric failed – silently fall back to password login
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biometric failed: use password instead')),
        );
      }
    }
  }

  Future<void> _login() async {
    final contact = _emailPhoneController.text.trim();
    final password = _passwordController.text;

    if (contact.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isEmail = contact.contains('@');

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: isEmail ? contact : null,
        phone: isEmail ? null : '+60$contact',
        password: password,
      );

      if (response.user != null && mounted) {
        await _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateAfterLogin() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) return;

    // Fetch the user's row from public.users
    final userData = await Supabase.instance.client
        .from('users')
        .select('role_id')
        .eq('user_id', user.id)
        .maybeSingle();

    if (userData == null) {
      // First time — create the row
      try {
        await Supabase.instance.client.from('users').insert({
          'user_id': user.id,
          'email': user.email,
          if (user.phone != null && user.phone!.isNotEmpty)
            'phone_num': user.phone,
        });
      } catch (_) {}
    }

    if (!mounted) return;

    final roleId = userData?['role_id'] as String?;

    // First login — check biometric preference
    final prefs = await SharedPreferences.getInstance();
    final hasSetBiometric = prefs.containsKey('biometric_enabled');

    if (!hasSetBiometric && _biometricAvailable) {
      // Ask about biometrics first — BiometricPromptScreen will handle
      // onward navigation after the user decides
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const BiometricPromptScreen()),
      );
      return;
    }

    // Route based on whether the user has already set a role
    if (roleId == null || roleId.isEmpty) {
      // No role yet — send to role selection / onboarding
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      );
    } else {
      // Role already set — go straight to the correct dashboard
      _navigateToDashboard(roleId);
    }
  }

  void _navigateToDashboard(String role) {
    // Import at top of file: import 'elderly_dashboard.dart';
    Widget dashboard;
    switch (role) {
      case 'elderly':
        dashboard = const ElderlyDashboard();
        break;
      default:
        // Caregiver or unknown — fall back to role selection for now
        dashboard = const RoleSelectionScreen();
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => dashboard),
    );
  }


  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _emailPhoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 48.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),

              // Title
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF1E6C8E), Color(0xFF43927A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
                child: const Text(
                  'Log In',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your email/phone number and\npassword to log in',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 48),

              // Email/Phone Number Label
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Email/Phone Number',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailPhoneController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Enter your email or phone number',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF55A47A), width: 1.5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                ),
              ),
              const SizedBox(height: 20),

              // Password Label
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Password',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF9CA3AF), size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF9CA3AF),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF55A47A), width: 1.5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                ),
              ),
              const SizedBox(height: 28),

              // Next / Login Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF55A47A),
                    disabledBackgroundColor: const Color(0xFF55A47A).withOpacity(0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Next',
                              style: TextStyle(
                                fontSize: 17,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                          ],
                        ),
                ),
              ),

              // Biometric login button (shown if available and enabled)
              if (_biometricAvailable && _biometricEnabled) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _loginWithBiometric,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fingerprint, color: Color(0xFF55A47A), size: 28),
                        SizedBox(width: 8),
                        Text(
                          'Login with Biometrics',
                          style: TextStyle(
                            color: Color(0xFF55A47A),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Or Text
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Or',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 24),

              // Continue with Google
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        'https://img.icons8.com/color/48/000000/google-logo.png',
                        width: 20,
                        height: 20,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.g_mobiledata, size: 24, color: Colors.blue),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Continue with Google',
                        style: TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Sign Up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    ),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: Color(0xFF55A47A),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
