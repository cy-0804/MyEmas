import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomSession {
  final String id;
  final String name;
  final TimeOfDay time;

  CustomSession({required this.id, required this.name, required this.time});

  factory CustomSession.fromMap(Map<String, dynamic> map) {
    final t = map['time'].toString().split(':');
    return CustomSession(
      id: map['id'],
      name: map['name'],
      time: TimeOfDay(hour: int.parse(t[0]), minute: int.parse(t[1])),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
  };
}

class SessionManager extends ChangeNotifier {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  List<CustomSession> _sessions = [];
  List<CustomSession> get sessions => _sessions;

  final List<CustomSession> defaultSessions = [
    CustomSession(id: 'morning', name: 'Morning', time: const TimeOfDay(hour: 8, minute: 0)),
    CustomSession(id: 'afternoon', name: 'Afternoon', time: const TimeOfDay(hour: 13, minute: 0)),
    CustomSession(id: 'night', name: 'Night', time: const TimeOfDay(hour: 20, minute: 0)),
  ];

  Future<void> init({String? userId}) async {
    _sessions = List.from(defaultSessions);
    final uid = userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      try {
        final res = await Supabase.instance.client
            .from('elderly')
            .select('custom_sessions')
            .eq('user_id', uid)
            .maybeSingle();
        
        if (res != null && res['custom_sessions'] != null) {
          final List<dynamic> decoded = jsonDecode(res['custom_sessions']);
          _sessions = decoded.map((e) => CustomSession.fromMap(e)).toList();
        }
      } catch (e) {
        debugPrint('Error loading custom sessions from DB: $e');
        // Fallback to local
        final prefs = await SharedPreferences.getInstance();
        final local = prefs.getString('custom_sessions');
        if (local != null) {
          final List<dynamic> decoded = jsonDecode(local);
          _sessions = decoded.map((e) => CustomSession.fromMap(e)).toList();
        }
      }
    }
    
    // Sort by time
    _sessions.sort((a, b) {
      if (a.time.hour == b.time.hour) return a.time.minute.compareTo(b.time.minute);
      return a.time.hour.compareTo(b.time.hour);
    });
    
    notifyListeners();
  }

  Future<void> updateSessions(List<CustomSession> newSessions, {String? userId}) async {
    newSessions.sort((a, b) {
      if (a.time.hour == b.time.hour) return a.time.minute.compareTo(b.time.minute);
      return a.time.hour.compareTo(b.time.hour);
    });
    
    _sessions = newSessions;
    final jsonStr = jsonEncode(_sessions.map((e) => e.toMap()).toList());
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_sessions', jsonStr);

    final uid = userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      try {
        await Supabase.instance.client
            .from('elderly')
            .update({'custom_sessions': jsonStr})
            .eq('user_id', uid);
      } catch (e) {
        debugPrint('Error saving custom sessions to DB: $e');
      }
    }
    notifyListeners();
  }
}
