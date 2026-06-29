import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient('https://aiyiatzcubpbczlbzhby.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFpeWlhdHpjdWJwYmN6bGJ6aGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczODAyODksImV4cCI6MjA5Mjk1NjI4OX0._I8nZMuTOQguVz_y_oDl3gCi5DP2R9lrGaydaUhWYQY');
  final res = await client.from('health_record').select('record_id, recorded_at').order('recorded_at', ascending: false).limit(5);
  print('--- Supabase Data ---');
  for (var r in res) {
    print(r);
  }
  print('--- Dart Times ---');
  print('Dart local time: \${DateTime.now()}');
  print('Dart UTC time: \${DateTime.now().toUtc()}');
}
