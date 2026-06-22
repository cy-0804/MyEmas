import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

void main() {
  test('Dump DB', () async {
    await dotenv.load(fileName: ".env");
    final url = 'https://aiyiatzcubpbczlbzhby.supabase.co';
    final key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFpeWlhdHpjdWJwYmN6bGJ6aGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczODAyODksImV4cCI6MjA5Mjk1NjI4OX0._I8nZMuTOQguVz_y_oDl3gCi5DP2R9lrGaydaUhWYQY';
    
    await Supabase.initialize(url: url, anonKey: key);
    final client = Supabase.instance.client;
    
    final meds = await client.from('medications').select();
    final sched = await client.from('schedule').select();
    
    File('d:\\utem\\FYP\\MyEmas\\db_dump.txt').writeAsStringSync('MEDS: $meds\n\nSCHED: $sched');
  });
}
