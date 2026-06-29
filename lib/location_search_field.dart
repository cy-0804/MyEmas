import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData prefixIcon;
  final Color themeColor;
  final String? Function(String?)? validator;

  const LocationSearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.themeColor = const Color(0xFF00539E),
    this.validator,
  });

  @override
  State<LocationSearchField> createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<LocationSearchField> {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String _lastQuery = '';
  List<String> _lastOptions = [];

  @override
  void dispose() {
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // Use a delay to prevent spamming API on every keystroke
  Future<List<String>> _searchLocations(String query) async {
    if (query.isEmpty) return [];
    if (query == _lastQuery) return _lastOptions;

    final completer = Completer<List<String>>();

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final request = await HttpClient().getUrl(Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&countrycodes=my'));
        request.headers.set('User-Agent', 'MyEmasApp/1.0 (dev@myemas.com)');
        final response = await request.close();
        final stringData = await response.transform(utf8.decoder).join();
        final List data = jsonDecode(stringData);

        _lastQuery = query;
        _lastOptions = data.map((e) => e['display_name'].toString()).toList();
        completer.complete(_lastOptions);
      } catch (e) {
        completer.complete([]);
      }
    });

    return completer.future;
  }

  void _openGoogleMaps(String query) async {
    final q = query.trim().isEmpty ? 'Malaysia' : query.trim();
    final url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch maps: $e')));
      }
    }
  }

  Future<void> _getCurrentLocation(TextEditingController localCtrl) async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      List<Placemark> p =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (p.isNotEmpty) {
        final addr =
            '${p.first.street}, ${p.first.subLocality}, ${p.first.locality}, ${p.first.administrativeArea}'
                .replaceAll(RegExp(r', ,'), ',');
        localCtrl.text = addr;
        widget.controller.text = addr;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not get location: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Autocomplete<String>(
          initialValue: TextEditingValue(text: widget.controller.text),
          optionsBuilder: (TextEditingValue textEditingValue) async {
            if (textEditingValue.text.length < 3) {
              return const Iterable<String>.empty();
            }
            return await _searchLocations(textEditingValue.text);
          },
          onSelected: (String selection) {
            widget.controller.text = selection;
            FocusScope.of(context).unfocus();
          },
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController textEditingController,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            // Keep internal controller synced if external controller changes
            textEditingController.addListener(() {
              if (widget.controller.text != textEditingController.text &&
                  !focusNode.hasFocus) {
                widget.controller.text = textEditingController.text;
              }
            });

            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 3,
              onChanged: (val) => widget.controller.text = val,
              validator: widget.validator,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                prefixIcon: Icon(widget.prefixIcon,
                    color: Colors.grey.shade500, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.my_location, color: widget.themeColor),
                      tooltip: 'Get current location',
                      onPressed: () => _getCurrentLocation(textEditingController),
                    ),
                    IconButton(
                      icon: const Icon(Icons.map, color: Colors.green),
                      tooltip: 'Search in Google Maps',
                      onPressed: () =>
                          _openGoogleMaps(textEditingController.text),
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: widget.themeColor),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<String> onSelected,
            Iterable<String> options,
          ) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 200,
                    maxWidth: constraints.maxWidth,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final option = options.elementAt(index);
                      return InkWell(
                        onTap: () {
                          onSelected(option);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            option,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
