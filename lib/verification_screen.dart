import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'role_selection_screen.dart';

class VerificationScreen extends StatefulWidget {
  final bool isEmail;
  final String contact; // The email address or phone number
  final String password; // Passed to login or insert into DB if needed

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
  final List<TextEditingController> _controllers = List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(8, (_) => FocusNode());
  bool _isLoading = false;

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyOTP() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 8) return;

    setState(() {
      _isLoading = true;
    });

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _insertIntoDatabase(String userId) async {
    try {
      // Insert into public.users
      final data = <String, dynamic>{
        'user_id': userId, // Both Email and Phone Auth from Supabase return valid UUIDs!
        'email': widget.isEmail ? widget.contact : null,
        'phone_num': widget.isEmail ? null : widget.contact,
        // other fields like fullname can be updated later in profile creation
      };

      // Ensure we don't insert null values as 'null' strings
      data.removeWhere((key, value) => value == null);

      await Supabase.instance.client.from('users').insert(data);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Created Successfully!')));
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("DB Error: ${e.toString()}")));
      }
    }
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 7) {
        FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
      } else {
        _focusNodes[index].unfocus();
        _verifyOTP(); // Automatically verify when the last digit is entered
      }
    } else {
      if (index > 0) {
        FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEmail ? 'Email Verification' : 'Phone Verification';
    final subtitle1 = widget.isEmail ? 'We’ll send a code to your email to' : 'We’ll send a code to your number to';
    final subtitle2 = 'confirm you own it.';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
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
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101113),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                subtitle1,
                style: const TextStyle(color: Color(0xFF454752), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              Text(
                subtitle2,
                style: const TextStyle(color: Color(0xFF454752), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // OTP Input Fields
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(8, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.0),
                    width: 36,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _focusNodes[index].hasFocus ? const Color(0xFF14EB80) : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF40434D)),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => _onChanged(value, index),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),

              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF51A77B))
              else
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      if (widget.isEmail) {
                        // Resend Email Logic
                        Supabase.instance.client.auth.resend(
                          type: OtpType.signup,
                          email: widget.contact,
                        );
                      } else {
                        // Resend SMS Logic
                        Supabase.instance.client.auth.resend(
                          type: OtpType.sms,
                          phone: widget.contact,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF51A77B), // Or BADDCC based on Figma state
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Resend Code',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
