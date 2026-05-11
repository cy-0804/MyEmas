import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Replace these with your actual URL and Anon Key
  await Supabase.initialize(
    url: 'https://aiyiatzcubpbczlbzhby.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFpeWlhdHpjdWJwYmN6bGJ6aGJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczODAyODksImV4cCI6MjA5Mjk1NjI4OX0._I8nZMuTOQguVz_y_oDl3gCi5DP2R9lrGaydaUhWYQY',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
