import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AiHealthService {
  static final _apiKey = dotenv.env['GEMINI_API_KEY'];
  
  static Future<String> generateSummary({
    required String elderlyId,
    required String timeframe, // 'day', 'week', 'month'
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'your_api_key_here') {
      return "⚠️ **API Key Missing**: Please configure your Gemini API Key in the `.env` file.";
    }

    try {
      final db = Supabase.instance.client;
      final now = DateTime.now();
      DateTime startDate;

      switch (timeframe) {
        case 'day': startDate = DateTime(now.year, now.month, now.day); break;
        case 'week': startDate = now.subtract(const Duration(days: 7)); break;
        case 'month': startDate = now.subtract(const Duration(days: 30)); break;
        default: startDate = now.subtract(const Duration(days: 7));
      }

      final res = await db
          .from('health_record')
          .select('blood_pressure, heart_rate, glucose_level, temperature, recorded_at')
          .eq('elderly_id', elderlyId)
          .gte('recorded_at', startDate.toUtc().toIso8601String())
          .order('recorded_at', ascending: true);

      final records = res as List<dynamic>;

      if (records.isEmpty) {
        return "No health records found for the past $timeframe. Please add some vitals first to generate an AI summary.";
      }

      final sb = StringBuffer();
      for (final r in records) {
        final date = DateTime.parse(r['recorded_at'] as String).toLocal();
        final dateStr = DateFormat('MMM d, h:mm a').format(date);
        sb.writeln("- $dateStr | BP: ${r['blood_pressure'] ?? 'N/A'} mmHg | HR: ${r['heart_rate'] ?? 'N/A'} bpm | Glucose: ${r['glucose_level'] ?? 'N/A'} mmol/L | Temp: ${r['temperature'] ?? 'N/A'}°C");
      }

      String chronicConditions = "Unknown";
      final elderlyRes = await db.from('elderly').select('chronic_condition').eq('user_id', elderlyId).maybeSingle();
      if (elderlyRes != null && elderlyRes['chronic_condition'] != null) {
        chronicConditions = elderlyRes['chronic_condition'] as String;
      }

      final prompt = '''
You are an expert, empathetic geriatric care assistant analyzing health records for an elderly patient.
Analyze the following vital signs recorded over the past $timeframe.

Patient Chronic Conditions: $chronicConditions

Data Records:
${sb.toString()}

Please provide a structured health summary formatted in clear, easy-to-read Markdown. Include:
1. **Overall Status**: A brief 2-sentence summary of their overall stability.
2. **Trends & Anomalies**: Identify any negative or positive trends (e.g., blood pressure slowly rising over the week). If any vitals are dangerously high/low, flag them prominently!
3. **Possible Health Problems**: State any potential conditions detected from these trends (e.g., Tachycardia, Hypoglycemia). 
4. **Actionable Recommendations**: 2-3 concise, actionable recommendations for the caregiver or patient.

Keep the tone professional yet caring. Do NOT include greetings or fluff. Output ONLY the markdown report.
''';

      // Try multiple endpoint/model combos until one works
      final modelsToTry = [
        'gemini-3.5-flash',
        'gemini-2.5-flash',
        'gemini-2.0-flash',
        'gemini-1.5-flash',
      ];

      final reqBody = jsonEncode({
        "contents": [
          {
            "parts": [{"text": prompt}]
          }
        ]
      });

      http.Response? successResponse;
      String lastError = 'No models tried';
      for (final model in modelsToTry) {
        // Try with AQ key header style (new format) and query param style (old format)
        final urls = [
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
          'https://generativelanguage.googleapis.com/v1/models/$model:generateContent',
        ];
        for (final url in urls) {
          final resp = await http.post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey!,
            },
            body: reqBody,
          );
          if (resp.statusCode == 200) {
            successResponse = resp;
            break;
          }
          lastError = 'Model: $model | Status: ${resp.statusCode} | ${resp.body.substring(0, resp.body.length.clamp(0, 200))}';
        }
        if (successResponse != null) break;
      }

      if (successResponse == null) {
        return "⚠️ Could not connect to any Gemini model.\n\nLast error:\n$lastError";
      }

      final data = jsonDecode(successResponse.body);
      final text = data['candidates'][0]['content']['parts'][0]['text'];
      return text as String;

    } catch (e) {
      return "⚠️ **Network Error generating AI Summary**: $e";
    }
  }

  static Future<Map<String, dynamic>> evaluateImmediateRisk({
    required String elderlyId,
    required String? bloodPressure,
    required int? heartRate,
    required double? glucoseLevel,
    required double? temperature,
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'your_api_key_here') {
      throw Exception("Gemini API Key Missing");
    }

    try {
      final db = Supabase.instance.client;
      String chronicConditions = "Unknown";
      final elderlyRes = await db.from('elderly').select('chronic_condition').eq('user_id', elderlyId).maybeSingle();
      if (elderlyRes != null && elderlyRes['chronic_condition'] != null) {
        chronicConditions = elderlyRes['chronic_condition'] as String;
      }

      final prompt = '''
You are an expert medical AI assistant. Analyze these exact vitals just recorded for an elderly patient with the following chronic conditions: $chronicConditions.

Vitals:
- Blood Pressure: ${bloodPressure ?? 'N/A'} mmHg
- Heart Rate: ${heartRate ?? 'N/A'} bpm
- Glucose Level: ${glucoseLevel ?? 'N/A'} mmol/L
- Temperature: ${temperature ?? 'N/A'} °C

Based on clinical guidelines for elderly patients, return ONLY a valid JSON object with the following exact keys:
"risk_level": strictly "low", "medium", or "high",
"recommendation": A single paragraph combining an explanation of the potential health risk, which specific metrics are concerning (if any), and a concise actionable recommendation.

Do not include markdown blocks, backticks, or any other text. Output purely the JSON object.
''';

      final modelsToTry = [
        'gemini-3.5-flash',
        'gemini-2.5-flash',
        'gemini-2.0-flash',
        'gemini-1.5-flash',
      ];

      final reqBody = jsonEncode({
        "contents": [
          {
            "parts": [{"text": prompt}]
          }
        ]
      });

      http.Response? successResponse;
      for (final model in modelsToTry) {
        final urls = [
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
          'https://generativelanguage.googleapis.com/v1/models/$model:generateContent',
        ];
        for (final url in urls) {
          final resp = await http.post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey!,
            },
            body: reqBody,
          );
          if (resp.statusCode == 200) {
            successResponse = resp;
            break;
          }
        }
        if (successResponse != null) break;
      }

      if (successResponse == null) {
        throw Exception("Could not connect to any Gemini model.");
      }

      final data = jsonDecode(successResponse.body);
      String text = data['candidates'][0]['content']['parts'][0]['text'];
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
      
      return jsonDecode(text) as Map<String, dynamic>;

    } catch (e) {
      throw Exception("AI Evaluation failed: $e");
    }
  }
}
