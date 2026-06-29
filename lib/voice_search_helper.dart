import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class VoiceSearchBar extends StatefulWidget {
  final Function(String command) onCommand;
  const VoiceSearchBar({super.key, required this.onCommand});

  @override
  State<VoiceSearchBar> createState() => _VoiceSearchBarState();
}

class _VoiceSearchBarState extends State<VoiceSearchBar> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _ctrl = TextEditingController();
  bool _isListening = false;

  void _listen() async {
    if (!_isListening) {
      final micStatus = await Permission.microphone.request();
      final speechStatus = await Permission.speech.request();
      
      if (micStatus.isPermanentlyDenied || speechStatus.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Microphone permission is blocked. Please enable it in Settings.'.tr()),
              action: SnackBarAction(
                label: 'Settings'.tr(),
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      } 
      // Even if status == denied (not permanently), we will still attempt to initialize 
      // because the speech_to_text library has its own built-in permission prompter 
      // that might work better on some physical devices.

      bool available = await _speech.initialize(
        debugLogging: true,
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') setState(() => _isListening = false);
        },
        onError: (val) {
          debugPrint('Speech onError: $val');
          setState(() => _isListening = false);
        },
      );
      if (available) {
        setState(() {
          _isListening = true;
          _ctrl.clear();
        });
        _speech.listen(
          onResult: (val) {
            _ctrl.text = val.recognizedWords;
            if (val.hasConfidenceRating && val.confidence > 0) {
              final cmd = val.recognizedWords.toLowerCase();
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted && _ctrl.text.toLowerCase() == cmd) {
                  widget.onCommand(cmd);
                  setState(() => _isListening = false);
                  _speech.stop();
                }
              });
            }
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech recognition not available on this device'.tr())),
          );
        }
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _submit(String val) {
    widget.onCommand(val.toLowerCase());
    _ctrl.clear();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: TextField(
        controller: _ctrl,
        onSubmitted: _submit,
        decoration: InputDecoration(
          hintText: 'Search function (e.g. "Add Medicine")'.tr(),
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFF51A77B))),
        ),
      ),
    );
  }
}
