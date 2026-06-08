import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'profile_success_screen.dart';

class CaregiverQrScreen extends StatefulWidget {
  const CaregiverQrScreen({super.key});

  @override
  State<CaregiverQrScreen> createState() => _CaregiverQrScreenState();
}

class _CaregiverQrScreenState extends State<CaregiverQrScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
  }

  Future<void> _downloadQrCode() async {
    // Request permission
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission is required to save QR code.')));
      }
      // Continue anyway, newer Android versions might work via MediaStore without explicit permission
    }

    try {
      final Uint8List? image = await _screenshotController.capture();
      if (image != null) {
        final result = await ImageGallerySaverPlus.saveImage(
          image,
          quality: 100,
          name: "MyEmas_Caregiver_QR_${DateTime.now().millisecondsSinceEpoch}",
        );
        if (mounted) {
          if (result['isSuccess'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR Code saved to gallery!')));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save QR code: ${result['errorMessage']}')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving QR code: $e')));
      }
    }
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            children: [
              const Text(
                'Let\'s Add Your Caregiver',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF27252E),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Caregiver can easily connect to your account to monitor your health remotely. Ask them to scan the QR below to connect.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Open Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6C7278),
                ),
              ),
              const SizedBox(height: 40),
              
              // QR Code Area
              Screenshot(
                controller: _screenshotController,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'MYEMAS QR',
                        style: TextStyle(
                          fontFamily: 'League Spartan',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF27252E),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_userId != null)
                        QrImageView(
                          data: _userId!,
                          version: QrVersions.auto,
                          size: 200.0,
                        )
                      else
                        const SizedBox(height: 200, width: 200, child: Center(child: Text("User ID missing"))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Download Button
              SizedBox(
                width: 280,
                height: 56,
                child: OutlinedButton(
                  onPressed: _downloadQrCode,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF51A77B), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download, color: Color(0xFF51A77B)),
                      SizedBox(width: 8),
                      Text(
                        'Download',
                        style: TextStyle(fontSize: 18, color: Color(0xFF51A77B), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Next Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileSuccessScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF51A77B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
