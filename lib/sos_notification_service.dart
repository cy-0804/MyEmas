import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

class SosNotificationService {
  static final SosNotificationService _instance = SosNotificationService._internal();
  factory SosNotificationService() => _instance;
  SosNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const int _sosNotifId = 9999;
  static const int _medNotifId = 8888;
  static const String _channelId = 'sos_emergency';
  static const String _medChannelId = 'medication_alerts';

  Timer? _repeatTimer;
  OverlayEntry? _overlayEntry;
  bool _initialized = false;

  // ─── Initialize ───────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Create high-priority SOS notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      'SOS Emergency Alerts',
      description: 'Urgent alerts when an elderly patient triggers SOS',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFFB71C1C),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Create medium-priority Medication notification channel
    const medChannel = AndroidNotificationChannel(
      _medChannelId,
      'Medication Alerts',
      description: 'Alerts when an elderly patient misses their medication',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFFF57C00),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(medChannel);
  }

  // ─── Show SOS Notification (Android system notification) ──────────────────
  Future<void> showSosNotification({
    required String elderlyName,
    required String location,
    required String alertId,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      'SOS Emergency Alerts',
      channelDescription: 'Urgent SOS alert from elderly patient',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ongoing: true,           // Cannot be swiped away
      autoCancel: false,       // Stays until explicitly dismissed
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      color: const Color(0xFFB71C1C),
      icon: '@mipmap/ic_launcher',
      actions: const [
        AndroidNotificationAction(
          'respond',
          '✅ I Am Responding',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    await _plugin.show(
      _sosNotifId,
      '🚨 SOS EMERGENCY — $elderlyName',
      '📍 $location\nTap to open app and confirm.',
      NotificationDetails(android: androidDetails),
      payload: alertId,
    );
  }

  // ─── Show Medication Notification ───────────────────────────────────────────
  Future<void> showMedicationNotification({
    required String elderlyName,
    required String message,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      _medChannelId,
      'Medication Alerts',
      channelDescription: 'Alerts when an elderly patient misses their medication',
      importance: Importance.high,
      priority: Priority.high,
      fullScreenIntent: false,
      ongoing: false,
      styleInformation: BigTextStyleInformation(
        message,
        htmlFormatBigText: true,
        contentTitle: '<b>$elderlyName Missed Medication</b>',
        htmlFormatContentTitle: true,
        summaryText: 'Medication Alert',
        htmlFormatSummaryText: true,
      ),
      color: const Color(0xFFF57C00),
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.show(
      _medNotifId,
      '$elderlyName Missed Medication',
      message,
      NotificationDetails(android: androidDetails),
    );
  }

  // ─── Start repeat notifications every 60s until confirmed ─────────────────
  void startRepeatNotification({
    required String elderlyName,
    required String location,
    required String alertId,
  }) {
    _repeatTimer?.cancel();
    // Show immediately
    showSosNotification(elderlyName: elderlyName, location: location, alertId: alertId);
    // Then repeat every 60 seconds
    _repeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      showSosNotification(elderlyName: elderlyName, location: location, alertId: alertId);
    });
  }

  // ─── Stop all notifications ────────────────────────────────────────────────
  Future<void> dismissSosNotification() async {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    await _plugin.cancel(_sosNotifId);
    dismissOverlay();
  }

  // ─── In-App Overlay (shows on top of all screens while app is open) ───────
  void showSosOverlay({
    required BuildContext context,
    required String elderlyName,
    required String location,
    required String alertId,
    required VoidCallback onConfirm,
  }) {
    dismissOverlay(); // Remove any existing overlay first

    _overlayEntry = OverlayEntry(
      builder: (_) => _SosBannerOverlay(
        elderlyName: elderlyName,
        location: location,
        onConfirm: () {
          onConfirm();
          dismissOverlay();
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void dismissOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

// ─── Overlay Widget ──────────────────────────────────────────────────────────
class _SosBannerOverlay extends StatefulWidget {
  final String elderlyName;
  final String location;
  final VoidCallback onConfirm;

  const _SosBannerOverlay({
    required this.elderlyName,
    required this.location,
    required this.onConfirm,
  });

  @override
  State<_SosBannerOverlay> createState() => _SosBannerOverlayState();
}

class _SosBannerOverlayState extends State<_SosBannerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (_, child) => Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color.lerp(
                const Color(0xFFB71C1C),
                const Color(0xFFD32F2F),
                _pulseController.value,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.4 + _pulseController.value * 0.3),
                  blurRadius: 20 + _pulseController.value * 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '🚨  SOS — CALL NOT ANSWERED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      DateFormat('h:mm a').format(DateTime.now()),
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.elderlyName} needs immediate help!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.location,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onConfirm,
                    icon: const Icon(Icons.check_circle, color: Color(0xFFB71C1C), size: 18),
                    label: const Text(
                      'I Am Responding — Confirm',
                      style: TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
