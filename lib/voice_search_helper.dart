import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') setState(() => _isListening = false);
        },
        onError: (val) => setState(() => _isListening = false),
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
          hintText: 'Search function (e.g. "Add Medicine")',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: IconButton(
            icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.red : Colors.grey),
            onPressed: _listen,
          ),
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
