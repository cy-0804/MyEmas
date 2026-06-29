import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:phone_state/phone_state.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:telephony/telephony.dart';

class SosService {
  static final SosService _instance = SosService._internal();
  factory SosService() => _instance;
  SosService._internal();

  // State
  bool _isActive = false;
  String? _alertId;
  Timer? _locationTimer;
  StreamSubscription? _phoneStateSubscription;
  int _currentCaregiverIndex = 0;
  List<Map<String, dynamic>> _caregivers = [];
  bool _callWasAnswered = false;
  Timer? _retryTimer;
  String? _lastAddress;
  Position? _lastPosition;

  bool get isActive => _isActive;
  String? get alertId => _alertId;

  // Callbacks for UI
  VoidCallback? onSosResolved;
  Function(String caregiver)? onCallingCaregiver;
  Function(String address)? onLocationUpdated;
  VoidCallback? onCallUnanswered; // fires when a call ends without being answered

  // ─── Trigger SOS ──────────────────────────────────────────────────────────
  Future<String?> triggerSos() async {
    if (_isActive) return null;

    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return 'Not logged in';

      // 1. Request location permission
      final locPerm = await Geolocator.requestPermission();
      if (locPerm == LocationPermission.denied ||
          locPerm == LocationPermission.deniedForever) {
        return 'Location permission denied. SOS cannot share your location.';
      }

      // 2. Get current position
      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
      } catch (e) {
        position = await Geolocator.getLastKnownPosition() ??
            Position(
              latitude: 0, longitude: 0,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0, altitudeAccuracy: 0,
              heading: 0, headingAccuracy: 0,
              speed: 0, speedAccuracy: 0,
            );
      }

      // 3. Convert to address
      String address = '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      try {
        final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = '${p.street}, ${p.subLocality}, ${p.locality}, ${p.administrativeArea}';
        }
      } catch (_) {}
      _lastAddress = address;
      _lastPosition = position;
      onLocationUpdated?.call(address);

      // 4. Fetch linked caregivers (primary first)
      final careRes = await db
          .from('care_link')
          .select('caregiver_id, relationship, emergency_contact_primary, caregiver:caregiver_id(users(fullname, phone_num))')
          .eq('elderly_id', uid)
          .order('emergency_contact_primary', ascending: false);
      
      _caregivers = List<Map<String, dynamic>>.from(careRes);
      if (_caregivers.isEmpty) return 'No linked caregiver found. Please link a caregiver first.';

      // 5. Insert into emergency_logs
      final locationJson = jsonEncode({'lat': position.latitude, 'lng': position.longitude, 'address': address});
      
      // Get first link_id for the primary caregiver
      final linkRes = await db
          .from('care_link')
          .select('link_id')
          .eq('elderly_id', uid)
          .order('emergency_contact_primary', ascending: false)
          .limit(1)
          .single();

      final insertRes = await db.from('emergency_logs').insert({
        'link_id': linkRes['link_id'],
        'elderly_id': uid,
        'status': 'active',
        'location': locationJson,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }).select('alert_id').single();

      _alertId = insertRes['alert_id'] as String;
      _isActive = true;
      _currentCaregiverIndex = 0;
      _callWasAnswered = false;

      // 6. Start periodic location updates (every 15s)
      _startLocationUpdates();

      // 7. Listen to phone state
      _listenToPhoneState();

      // 8. Dial first caregiver
      await _dialCurrentCaregiver();

      return null; // null = success
    } catch (e) {
      debugPrint('SOS trigger error: $e');
      return 'SOS Error: $e';
    }
  }

  // ─── Dial current caregiver ───────────────────────────────────────────────
  Future<void> _dialCurrentCaregiver() async {
    if (_caregivers.isEmpty) return;
    final caregiver = _caregivers[_currentCaregiverIndex % _caregivers.length];
    final caregiverData = caregiver['caregiver'] as Map<String, dynamic>?;
    final userData = caregiverData?['users'] as Map<String, dynamic>?;
    final phone = userData?['phone_num'] as String?;
    final name = userData?['fullname'] as String? ?? 'Caregiver';

    onCallingCaregiver?.call(name);
    debugPrint('SOS: Calling $name at $phone');

    if (phone == null || phone.isEmpty) {
      debugPrint('SOS: No phone number for $name, skipping...');
      _currentCaregiverIndex++;
      _dialCurrentCaregiver();
      return;
    }

    // Check permissions (they should have been requested earlier)
    final isCallGranted = await Permission.phone.isGranted;
    final isSmsGranted = await Permission.sms.isGranted;

    // Clean phone number (remove spaces, hyphens, etc.)
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');

    // Send SMS Automatically in the background
    try {
      // Due to Malaysian MCMC directives, SMS containing URLs are BLOCKED by telcos.
      // We must only send the text address. The caregiver app will receive the exact map link via push notification.
      final msg = 'SOS EMERGENCY! I need help immediately. Location: ${_lastAddress ?? 'Unknown'}.';
      
      if (isSmsGranted) {
        final Telephony telephony = Telephony.instance;
        await telephony.sendSms(
          to: cleanPhone,
          message: msg,
        );
        debugPrint('SOS: Background SMS sent successfully to $cleanPhone.');
      } else {
        debugPrint('SOS: SMS permission denied, falling back to Intent.');
        final smsIntent = AndroidIntent(
          action: 'android.intent.action.SENDTO',
          data: 'smsto:$cleanPhone',
          arguments: {'sms_body': msg},
        );
        await smsIntent.launch();
      }
    } catch (e) {
      debugPrint('SOS: Failed to send background SMS: $e');
    }

    // Small delay to ensure SMS finishes sending before call takes over
    await Future.delayed(const Duration(milliseconds: 1000));
    
    if (isCallGranted) {
      // ACTION_CALL: immediately dials without user needing to tap
      final intent = AndroidIntent(
        action: 'android.intent.action.CALL',
        data: 'tel:$phone',
      );
      await intent.launch();
    } else {
      // Fallback: open dialer if permission denied
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }
  }

  // ─── Phone state listener ───────────────────────────────────────────────
  void _listenToPhoneState() async {
    _callWasAnswered = false;

    _phoneStateSubscription = PhoneState.stream.listen((event) {
      debugPrint('Phone state: ${event.status}');
      switch (event.status) {
        case PhoneStateStatus.CALL_STARTED:
          // Call was answered — set flag, do NOT send unanswered notification
          _callWasAnswered = true;
          break;
        case PhoneStateStatus.CALL_INCOMING:
        case PhoneStateStatus.CALL_ENDED:
          if (!_callWasAnswered && _isActive) {
            // Call ended WITHOUT being answered — notify caregiver
            _markCallUnanswered();
            // Try next caregiver after 3s
            _retryTimer?.cancel();
            _retryTimer = Timer(const Duration(seconds: 3), () {
              if (_isActive && !_callWasAnswered) {
                _currentCaregiverIndex++;
                _callWasAnswered = false;
                _dialCurrentCaregiver();
              }
            });
          } else if (_callWasAnswered && _isActive) {
            // Call was answered — reset flag for potential re-dial, no notification
            _callWasAnswered = false;
          }
          break;
        case PhoneStateStatus.NOTHING:
          break;
      }
    });
  }

  // Mark call as unanswered in DB so caregiver gets notified
  Future<void> _markCallUnanswered() async {
    if (_alertId == null) return;
    try {
      await Supabase.instance.client.from('emergency_logs').update({
        'call_status': 'unanswered',
      }).eq('alert_id', _alertId!);
      debugPrint('SOS: call_status set to unanswered');
      onCallUnanswered?.call();
    } catch (e) {
      debugPrint('SOS: failed to mark unanswered: $e');
    }
  }

  // ─── Periodic location updates ────────────────────────────────────────────
  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!_isActive || _alertId == null) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        String address = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        try {
          final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            address = '${p.street}, ${p.subLocality}, ${p.locality}';
          }
        } catch (_) {}

        _lastPosition = pos;
        _lastAddress = address;

        final locationJson = jsonEncode({'lat': pos.latitude, 'lng': pos.longitude, 'address': address});
        await Supabase.instance.client.from('emergency_logs').update({
          'location': locationJson,
        }).eq('alert_id', _alertId!);

        onLocationUpdated?.call(address);
      } catch (e) {
        debugPrint('Location update error: $e');
      }
    });
  }

  // ─── Cancel SOS ───────────────────────────────────────────────────────────
  Future<void> cancelSos() async {
    _isActive = false;
    _locationTimer?.cancel();
    _locationTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _phoneStateSubscription?.cancel();
    _phoneStateSubscription = null;

    if (_alertId != null) {
      try {
        await Supabase.instance.client.from('emergency_logs').update({
          'status': 'resolved',
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('alert_id', _alertId!);
      } catch (e) {
        debugPrint('Cancel SOS DB error: $e');
      }
    }

    _alertId = null;
    _caregivers = [];
    _currentCaregiverIndex = 0;
    onSosResolved?.call();
  }

  // ─── Manual retry call ─────────────────────────────────────────────────────
  Future<void> retryCall() async {
    _callWasAnswered = false;
    _currentCaregiverIndex++;
    await _dialCurrentCaregiver();
  }
}
