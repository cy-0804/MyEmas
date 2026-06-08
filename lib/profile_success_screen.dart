import 'package:flutter/material.dart';
import 'elderly_dashboard.dart';

class ProfileSuccessScreen extends StatelessWidget {
  const ProfileSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Success Icon / Image
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFF51A77B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 80, color: Colors.white),
              ),
              const SizedBox(height: 40),
              const Text(
                'Your profile is finalized!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF27252E),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  'You\'re all set! Enjoy MyEmas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Open Sans',
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const ElderlyDashboard()),
                        (route) => false, // Remove all previous routes
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF51A77B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 5,
                      shadowColor: const Color(0xFF51A77B).withOpacity(0.3),
                    ),
                    child: const Text(
                      'Go to Home',
                      style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
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
