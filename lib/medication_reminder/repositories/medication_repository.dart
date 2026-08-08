import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/medication_dose.dart';

class MedicationDoseRepository {
  static const String _dosesKey = 'medication_doses';

  // Save a dose locally
  Future<void> saveDose(MedicationDose dose) async {
    final prefs = await SharedPreferences.getInstance();
    final doses = await getAllDoses();
    
    // Remove if exists to update
    doses.removeWhere((d) => d.id == dose.id);
    doses.add(dose);
    
    final dosesJson = doses.map((d) => jsonEncode(d.toMap())).toList();
    await prefs.setStringList(_dosesKey, dosesJson);
  }

  // Retrieve all local doses
  Future<List<MedicationDose>> getAllDoses() async {
    final prefs = await SharedPreferences.getInstance();
    final dosesJson = prefs.getStringList(_dosesKey) ?? [];
    
    return dosesJson.map((jsonStr) => MedicationDose.fromMap(jsonDecode(jsonStr))).toList();
  }

  // Get a specific dose
  Future<MedicationDose?> getDose(String id) async {
    final doses = await getAllDoses();
    try {
      return doses.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  // Remove a dose
  Future<void> removeDose(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final doses = await getAllDoses();
    
    doses.removeWhere((d) => d.id == id);
    
    final dosesJson = doses.map((d) => jsonEncode(d.toMap())).toList();
    await prefs.setStringList(_dosesKey, dosesJson);
  }
}
