import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ─── colour tokens ────────────────────────────────────────────────────────────
const _kGreen = Color(0xFF51A77B);

class CaregiverScanQrScreen extends StatefulWidget {
  const CaregiverScanQrScreen({super.key});
  @override
  State<CaregiverScanQrScreen> createState() => _CaregiverScanQrScreenState();
}

class _CaregiverScanQrScreenState extends State<CaregiverScanQrScreen> {
  bool _scanned = false;
  bool _linking = false;
  String? _status;
  MobileScannerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _linking) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() { _scanned = true; _linking = true; _status = 'Connecting to patient...'; });

    try {
      final db = Supabase.instance.client;
      final caregiverId = db.auth.currentUser?.id;
      if (caregiverId == null) throw Exception('Not logged in');

      // Validate that the scanned UUID belongs to an elderly user
      final userRow = await db.from('users').select('user_id, fullname, role_id').eq('user_id', code).maybeSingle();
      if (userRow == null) throw Exception('Invalid QR code – user not found');
      if (userRow['role_id'] != 'elderly') throw Exception('This QR belongs to a non-elderly account');

      // Make sure elderly record exists
      final elderlyRow = await db.from('elderly').select('user_id').eq('user_id', code).maybeSingle();
      if (elderlyRow == null) {
        await db.from('elderly').insert({'user_id': code});
      }

      // Ensure caregiver record exists
      final caregiverRow = await db.from('caregiver').select('user_id').eq('user_id', caregiverId).maybeSingle();
      if (caregiverRow == null) {
        await db.from('caregiver').insert({'user_id': caregiverId});
      }

      // Check if already linked
      final existing = await db
          .from('care_link')
          .select('link_id')
          .eq('elderly_id', code)
          .eq('caregiver_id', caregiverId)
          .maybeSingle();

      if (existing != null) {
        setState(() { _status = 'Already linked to ${userRow['fullname'] ?? 'this patient'}'; _linking = false; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // Create care link
      await db.from('care_link').insert({
        'elderly_id': code,
        'caregiver_id': caregiverId,
        'relationship': 'caregiver',
        'emergency_contact_primary': false,
      });

      setState(() { _status = '✅ Successfully linked to ${userRow['fullname'] ?? 'patient'}!'; _linking = false; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, true);
    } catch (e, stack) {
      debugPrint('QR Scan error: $e\n$stack');
      setState(() { _status = '❌ ${e.toString().replaceAll('Exception: ', '')}'; _scanned = false; _linking = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _status = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Patient QR', style: TextStyle(color: Colors.white, fontFamily: 'League Spartan', fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, false),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller?.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: () => _controller?.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera view
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
          ),

          // Scanner overlay
          _buildScannerOverlay(),

          // Bottom instruction
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  if (_linking)
                    const CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: _status!.startsWith('✅') ? _kGreen.withOpacity(0.9) : Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_status!, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  ],
                  if (_status == null && !_linking) ...[
                    const Icon(Icons.qr_code, color: Colors.white70, size: 32),
                    const SizedBox(height: 12),
                    const Text(
                      'Point your camera at the elderly\npatient\'s QR code',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Text('The QR code can be found in the patient\'s MyEmas app',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = constraints.maxWidth * 0.65;
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight * 0.4;
        final left = cx - size / 2;
        final top = cy - size / 2;

        return Stack(
          children: [
            // Dark overlay with hole
            ClipPath(
              clipper: _HoleClipper(left: left, top: top, size: size),
              child: Container(color: Colors.black.withOpacity(0.6)),
            ),
            // Corner decorations
            ...[ [left, top], [left + size - 28, top], [left, top + size - 28], [left + size - 28, top + size - 28] ]
                .asMap()
                .entries
                .map((e) {
              final pos = e.value;
              final idx = e.key;
              return Positioned(
                left: pos[0],
                top: pos[1],
                child: _Corner(flip: idx % 2 == 1, flipV: idx >= 2),
              );
            }),
            // Center crosshair
            Positioned(
              left: cx - 16, top: cy - 16,
              child: const _ScanimationDot(),
            ),
          ],
        );
      },
    );
  }
}

// ─── Hole clipper ─────────────────────────────────────────────────────────────
class _HoleClipper extends CustomClipper<Path> {
  final double left, top, size;
  const _HoleClipper({required this.left, required this.top, required this.size});

  @override
  Path getClip(Size s) {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, s.width, s.height))
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, size, size), const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(_HoleClipper old) => false;
}

// ─── Corner decoration ────────────────────────────────────────────────────────
class _Corner extends StatelessWidget {
  final bool flip, flipV;
  const _Corner({required this.flip, required this.flipV});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flip ? -1 : 1,
      scaleY: flipV ? -1 : 1,
      child: CustomPaint(size: const Size(28, 28), painter: _CornerPainter()),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF51A77B)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(0, 16), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(16, 0), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Animated scanning dot ────────────────────────────────────────────────────
class _ScanimationDot extends StatefulWidget {
  const _ScanimationDot();
  @override
  State<_ScanimationDot> createState() => _ScanimationDotState();
}

class _ScanimationDotState extends State<_ScanimationDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF51A77B), width: 2),
          ),
          child: const Center(child: Icon(Icons.add, color: Color(0xFF51A77B), size: 14)),
        ),
      ),
    );
  }
}
