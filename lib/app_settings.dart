import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  double _textScaleFactor = 1.0;
  String _language = 'English';

  double get textScaleFactor => _textScaleFactor;
  String get language => _language;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.0;
    _language = prefs.getString('language') ?? 'English';
    notifyListeners();
  }

  Future<void> setTextScaleFactor(double value) async {
    _textScaleFactor = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('textScaleFactor', value);
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    _language = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
    notifyListeners();
  }
}
