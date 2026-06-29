import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'sos_service.dart';

class SosActiveScreen extends StatefulWidget {
  const SosActiveScreen({super.key});

  @override
  State<SosActiveScreen> createState() => _SosActiveScreenState();
}

class _SosActiveScreenState extends State<SosActiveScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  final SosService _sos = SosService();

  String _callingName = 'Caregiver';
  String _location = 'Fetching location...';
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _sos.onCallingCaregiver = (name) {
      if (mounted) setState(() => _callingName = name);
    };
    _sos.onLocationUpdated = (addr) {
      if (mounted) setState(() => _location = addr);
    };
    // onSosResolved intentionally not set here — only _cancelSos() navigates back
    // to prevent double-pop black screen bug

    // Start SOS immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final error = await _sos.triggerSos();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  Future<void> _cancelSos() async {
    setState(() => _cancelling = true);
    await _sos.cancelSos();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent accidental back button
      child: Scaffold(
        backgroundColor: const Color(0xFFB71C1C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // ── Header ──
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'SOS EMERGENCY'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Help is being called'.tr(),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 48),

                // ── Pulsing SOS Icon ──
                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _rippleController,
                      builder: (_, _) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Ripple rings
                            for (int i = 0; i < 3; i++) _buildRipple(i),
                            // Center SOS circle
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (_, _) => Transform.scale(
                                scale: 1.0 + _pulseController.value * 0.08,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        blurRadius: 30,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'SOS'.tr(),
                                      style: const TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFB71C1C),
                                        letterSpacing: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // ── Calling Status ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.phone_in_talk_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${'Calling'.tr()} $_callingName...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _location,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'If the call is not answered, the next caregiver will be called automatically.'
                      .tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Cancel Button ──
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _cancelling ? null : _cancelSos,
                    icon: _cancelling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Color(0xFFB71C1C),
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.cancel_outlined,
                            color: Color(0xFFB71C1C),
                          ),
                    label: Text(
                      _cancelling
                          ? 'Cancelling...'.tr()
                          : 'Cancel SOS — I am Safe'.tr(),
                      style: const TextStyle(
                        color: Color(0xFFB71C1C),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRipple(int index) {
    final delay = index / 3;
    final animValue = (_rippleController.value + delay) % 1.0;
    final size = 140.0 + (animValue * 180.0);
    final opacity = (1.0 - animValue) * 0.4;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}
