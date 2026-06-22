import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  final apiKey = dotenv.env['GEMINI_API_KEY'];
  
  if (apiKey == null || apiKey.isEmpty) {
    print('No API key found in .env');
    exit(1);
  }
  
  print('Testing API Key starting with: \${apiKey.substring(0, 5)}...');
  
  final modelsToTest = [
    'gemini-1.5-flash',
    'gemini-1.5-flash-latest',
    'gemini-1.5-pro',
    'gemini-pro',
    'gemini-1.0-pro'
  ];
  
  for (final modelName in modelsToTest) {
    print('\\n--- Testing model: \$modelName ---');
    try {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      final response = await model.generateContent([Content.text('Say hello')]);
      print('✅ SUCCESS! \$modelName works. Response: \${response.text}');
      exit(0); // Exit on first success
    } catch (e) {
      print('❌ FAILED: \$e');
    }
  }
}
