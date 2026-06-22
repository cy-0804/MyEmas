import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final envFile = File('.env');
  final lines = await envFile.readAsLines();
  String url = '';
  String key = '';
  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.substring('SUPABASE_URL='.length);
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.substring('SUPABASE_ANON_KEY='.length);
  }
  
  final client = SupabaseClient(url, key);
  
  final meds = await client.from('medications').select();
  print('MEDS: $meds');
  
  final sched = await client.from('schedule').select();
  print('SCHED: $sched');
  
  exit(0);
}
