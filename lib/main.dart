import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'medication_dashboard_view.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io' as dart_io;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();

  // Replace these with your actual URL and Anon Key
  await Supabase.initialize(
    url: 'https://aiyiatzcubpbczlbzhby.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFpeWlhdHpjdWJwYmN6bGJ6aGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczODAyODksImV4cCI6MjA5Mjk1NjI4OX0._I8nZMuTOQguVz_y_oDl3gCi5DP2R9lrGaydaUhWYQY',
  );

  await initMedicationNotifications();
  _dumpDb();

  runApp(const MyApp());
}

Future<void> _dumpDb() async {
  try {
    debugPrint('=== DUMPING DATABASE ===');
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null) {
      debugPrint('No current user.');
      return;
    }
    debugPrint('Current user: ${u.id}');
    final scheds = await Supabase.instance.client.from('schedule').select().eq('elderly_id', u.id);
    debugPrint('Schedules: ${scheds.length}');
    for (var s in scheds as List) {
      debugPrint(' - Schedule: ${s['schedule_id']} | title: ${s['title']} | notes: ${s['notes']}');
    }
    
    final meds = await Supabase.instance.client.from('medications').select();
    debugPrint('All Medications in DB: ${meds.length}');
    for (var m in meds as List) {
      debugPrint(' - Med RAW: $m');
      if (m['schedule_id'] == null) {
        debugPrint('CLEANING ORPHANED MEDICATION: ${m['medication_id']}');
        await Supabase.instance.client.from('medications').delete().eq('medication_id', m['medication_id']);
      }
    }
    debugPrint('=== END DUMP & CLEANUP ===');
  } catch (e, st) {
    debugPrint('Dump Error: $e\n$st');
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MyEmas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF53A37A)),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
