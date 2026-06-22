import 'package:supabase/supabase.dart';

Future<void> main() async {
  final client = SupabaseClient(
    'https://aiyiatzcubpbczlbzhby.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFpeWlhdHpjdWJwYmN6bGJ6aGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczODAyODksImV4cCI6MjA5Mjk1NjI4OX0._I8nZMuTOQguVz_y_oDl3gCi5DP2R9lrGaydaUhWYQY',
  );
  try {
    final res = await client.from('medications').select().limit(1);
    if (res.isNotEmpty) {
      print('Medication columns: ${res.first.keys.toList()}');
    } else {
      print('Medication table is empty.');
    }
  } catch (e) {
    print('Error: $e');
  }
}
