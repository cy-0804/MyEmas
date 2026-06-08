import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_created_screen.dart';

class VerificationScreen extends StatefulWidget {
  final bool isEmail;
  final String contact;
  final String password;

  const VerificationScreen({
    super.key,
    required this.isEmail,
    required this.contact,
    required this.password,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  // 6 OTP boxes (Figma shows 6-8; Supabase email OTP is 6 digits)
  static const int _otpLength = 6;
  final List<TextEditingController> _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(_otpLength, (_) => FocusNode());

  bool _isLoading = false;
  bool _canResend = false;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    setState(() {
      _canResend = false;
      _secondsLeft = 30;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _canResend = true);
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < _otpLength - 1) {
        FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
      } else {
        _focusNodes[index].unfocus();
        // Auto-verify when all digits are entered
        if (_otp.length == _otpLength) _verifyOTP();
      }
    } else {
      if (index > 0) {
        FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
      }
    }
  }

  Future<void> _verifyOTP() async {
    final code = _otp;
    if (code.length < _otpLength) {
      _showSnack('Please enter the complete verification code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.isEmail) {
        final response = await Supabase.instance.client.auth.verifyOTP(
          type: OtpType.signup,
          email: widget.contact,
          token: code,
        );
        if (response.user != null) {
          await _insertIntoDatabase(response.user!.id);
        }
      } else {
        final response = await Supabase.instance.client.auth.verifyOTP(
          type: OtpType.sms,
          phone: widget.contact,
          token: code,
        );
        if (response.user != null) {
          await _insertIntoDatabase(response.user!.id);
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Invalid code. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _insertIntoDatabase(String userId) async {
    try {
      final data = <String, dynamic>{
        'user_id': userId,
        'email': widget.isEmail ? widget.contact : null,
        'phone_num': widget.isEmail ? null : widget.contact,
      };
      data.removeWhere((key, value) => value == null);
      await Supabase.instance.client.from('users').insert(data);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AccountCreatedScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) _showSnack('Error: ${e.toString()}');
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;
    setState(() => _canResend = false); // prevent double-tap
    try {
      if (widget.isEmail) {
        await Supabase.instance.client.auth.resend(
          type: OtpType.signup,
          email: widget.contact,
        );
      } else {
        await Supabase.instance.client.auth.resend(
          type: OtpType.sms,
          phone: widget.contact,
        );
      }
      _showSnack('✉️ Verification code resent! Check your inbox.');
      _startCountdown();
    } catch (e) {
      _showSnack('Failed to resend: ${e.toString()}');
      setState(() => _canResend = true); // re-enable on failure
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF101113)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Verification',
          style: TextStyle(
            color: Color(0xFF101113),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // Title
              Text(
                widget.isEmail ? 'Email Verification' : 'Phone Verification',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF101113),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                widget.isEmail
                    ? "We'll send a code to your email to\nconfirm you own it."
                    : "We'll send a code to your number to\nconfirm you own it.",
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 15,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // OTP Input Boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_otpLength, (index) {
                  return AnimatedBuilder(
                    animation: _focusNodes[index],
                    builder: (context, _) {
                      final isFocused = _focusNodes[index].hasFocus;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        width: 44,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF55A47A)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF101113),
                          ),
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) => _onChanged(value, index),
                        ),
                      );
                    },
                  );
                }),
              ),

              const SizedBox(height: 40),

              // Resend Code Button
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF55A47A))
              else ...[
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _canResend ? _resendCode : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canResend
                          ? const Color(0xFF55A47A)
                          : const Color(0xFFBADDCC),
                      disabledBackgroundColor: const Color(0xFFBADDCC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _canResend
                          ? 'Resend Code'
                          : 'Resend Code (0:${_secondsLeft.toString().padLeft(2, '0')})',
                      style: TextStyle(
                        fontSize: 16,
                        color: _canResend ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Verify Button (manual submit)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _verifyOTP,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF55A47A)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Verify',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF55A47A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
