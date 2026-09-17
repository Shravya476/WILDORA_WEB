import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ManualSearchSheet extends StatefulWidget {
  final void Function(double lat, double lon, String placeName, int hour, int minute) onSearch;

  const ManualSearchSheet({super.key, required this.onSearch});

  @override
  State<ManualSearchSheet> createState() => _ManualSearchSheetState();
}

class _ManualSearchSheetState extends State<ManualSearchSheet> {
  final _placeController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();

  bool _searching = false;
  bool _listening = false;
  bool _speechAvailable = false;
  String _speechStatus = '';
  String _error = '';
  bool _autoSearchScheduled = false;
  int _voiceSearchToken = 0;
  final stt.SpeechToText _speech = stt.SpeechToText();
  late TimeOfDay _selectedTime;
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;

  final List<Map<String, dynamic>> _presets = const [
    {'name': 'Nagarhole', 'lat': 11.93, 'lon': 76.13},
    {'name': 'Bandipur', 'lat': 11.67, 'lon': 76.63},
    {'name': 'Wayanad', 'lat': 11.61, 'lon': 76.13},
    {'name': 'Mudumalai', 'lat': 11.56, 'lon': 76.52},
    {'name': 'Kudremukh', 'lat': 13.15, 'lon': 75.25},
    {'name': 'Kodagu', 'lat': 12.42, 'lon': 75.74},
    {'name': 'BRT Hills', 'lat': 11.98, 'lon': 77.05},
    {'name': 'Anamalai', 'lat': 10.57, 'lon': 76.93},
    {'name': 'Bengaluru', 'lat': 12.97, 'lon': 77.59},
    {'name': 'Mysuru', 'lat': 12.30, 'lon': 76.64},
    {'name': 'Bannerghatta Forest area', 'lat': 12.8000, 'lon': 77.5750},
    {'name': 'Turahalli Forest', 'lat': 12.8810, 'lon': 77.5310},
    {'name': 'Bannerghatta National Park', 'lat': 12.8000, 'lon': 77.5770},
    {'name': 'Nandi Hills area', 'lat': 13.3700, 'lon': 77.6830},
    {'name': 'Savandurga area', 'lat': 12.9200, 'lon': 77.2900},
    {'name': 'Devarayanadurga', 'lat': 13.3900, 'lon': 77.2200},
    {'name': 'Junnar, Maharashtra', 'lat': 19.21, 'lon': 73.88},
    {'name': 'Rajaji landscape, Uttarakhand', 'lat': 30.03, 'lon': 78.25},
    {'name': 'Udalguri, Assam', 'lat': 26.75, 'lon': 92.10},
    {'name': 'Sariska landscape, Rajasthan', 'lat': 27.33, 'lon': 76.44},
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);
    _hourController = TextEditingController(text: now.hour.toString().padLeft(2, '0'));
    _minuteController = TextEditingController(text: now.minute.toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _placeController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _hourController.dispose();
    _speech.stop();
    _minuteController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _speechStatus = status;
            if (status == 'listening') {
              _listening = true;
            } else if (status == 'done' || status == 'notListening') {
              _listening = false;
            }
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _speechStatus = 'Speech error';
            _error = 'Voice search could not hear you. Click the microphone, allow the microphone permission, and say the place name clearly.';
          });
        },
      );
      if (mounted) setState(() => _speechAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  void _scheduleVoiceAutoSearch({Duration delay = const Duration(milliseconds: 700)}) {
    if (_autoSearchScheduled) return;
    if (_placeController.text.trim().isEmpty || _searching) return;

    _autoSearchScheduled = true;
    final token = ++_voiceSearchToken;
    Future.delayed(delay, () {
      _autoSearchScheduled = false;
      if (!mounted || token != _voiceSearchToken) return;
      if (_placeController.text.trim().isNotEmpty && !_searching) {
        _searchPlace();
      }
    });
  }

  Future<void> _toggleVoiceSearch() async {
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        setState(() => _error = 'Voice search is not available. Allow microphone access in your browser/device settings.');
        return;
      }
    }

    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() {
      _error = '';
      _speechStatus = 'listening';
      _listening = true;
    });

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onResult: (value) {
          if (!mounted) return;
          final words = value.recognizedWords.trim();
          if (words.isNotEmpty) {
            _placeController.value = TextEditingValue(
              text: words,
              selection: TextSelection.collapsed(offset: words.length),
            );
          }
          if (value.finalResult && words.isNotEmpty) {
            setState(() => _listening = false);
            _speech.stop();
            // Voice search is automatic: once the final words are received,
            // wait briefly for the controller to settle, then search.
            _scheduleVoiceAutoSearch(delay: const Duration(milliseconds: 700));
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = 'Voice search could not start. Please allow microphone access in Chrome/Edge and try again.';
        });
      }
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _selectedTime, helpText: 'Choose prediction time');
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
        _hourController.text = picked.hour.toString().padLeft(2, '0');
        _minuteController.text = picked.minute.toString().padLeft(2, '0');
      });
    }
  }

  bool _readManualTime() {
    final h = int.tryParse(_hourController.text.trim());
    final m = int.tryParse(_minuteController.text.trim());
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      setState(() => _error = 'Enter a valid time: hour 0–23 and minute 0–59.');
      return false;
    }
    _selectedTime = TimeOfDay(hour: h, minute: m);
    return true;
  }

  Future<void> _searchPlace() async {
    if (!_readManualTime()) return;
    final query = _placeController.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Enter a place name.');
      return;
    }
    setState(() { _searching = true; _error = ''; });

    // Resolve the four reference wildlife-zone places locally. This makes
    // Predict Risk work for these names even when the online geocoder is
    // temporarily unavailable.
    final q = query.toLowerCase();
    final known = _presets.where((p) {
      final n = p['name'].toString().toLowerCase();
      return (q.contains('junnar') && n.contains('junnar')) ||
          (q.contains('rajaji') && n.contains('rajaji')) ||
          (q.contains('udalguri') && n.contains('udalguri')) ||
          (q.contains('sariska') && n.contains('sariska')) ||
          (q.contains('bannerghatta') && n.contains('bannerghatta')) ||
          (q.contains('turahalli') && n.contains('turahalli')) ||
          (q.contains('nandi hill') && n.contains('nandi hills')) ||
          (q.contains('savandurga') && n.contains('savandurga')) ||
          (q.contains('devarayanadurga') && n.contains('devarayanadurga'));
    }).toList();

    if (known.isNotEmpty) {
      final p = known.first;
      widget.onSearch(
        (p['lat'] as num).toDouble(),
        (p['lon'] as num).toDouble(),
        p['name'].toString(),
        _selectedTime.hour,
        _selectedTime.minute,
      );
      return;
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$query, India', 'format': 'jsonv2', 'limit': '1',
      });
      final response = await http.get(uri, headers: const {
        'Accept': 'application/json', 'User-Agent': 'WILDORA-HWC-App',
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('Search failed');
      final data = jsonDecode(response.body);
      if (data is! List || data.isEmpty) {
        setState(() { _searching = false; _error = 'Place not found. Try a nearby town, district or landmark.'; });
        return;
      }
      final item = data.first as Map<String, dynamic>;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      final display = item['display_name']?.toString() ?? query;
      if (lat == null || lon == null) throw Exception('No coordinates');
      widget.onSearch(lat, lon, display, _selectedTime.hour, _selectedTime.minute);
    } catch (_) {
      if (mounted) setState(() { _searching = false; _error = 'Could not search that place. Check your internet connection.'; });
    }
  }

  void _useCoordinates() {
    if (!_readManualTime()) return;
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null) {
      setState(() => _error = 'Enter valid latitude and longitude.');
      return;
    }
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      setState(() => _error = 'Latitude must be -90 to 90 and longitude -180 to 180.');
      return;
    }
    widget.onSearch(lat, lon, 'Selected coordinates', _selectedTime.hour, _selectedTime.minute);
  }

  void _preset(Map<String, dynamic> p) {
    _placeController.text = p['name'].toString();
    _latController.text = p['lat'].toString();
    _lonController.text = p['lon'].toString();
  }

  String _timeText() => _selectedTime.format(context);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 18),
          const Text('Predict a place', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0B2616))),
          const SizedBox(height: 5),
          const Text('Enter any place and choose the exact time you want WILDORA to check.', style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4)),
          const SizedBox(height: 17),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Semantics(
                textField: true,
                label: 'Place name. Type a location or use voice search.',
                child: TextField(
                  controller: _placeController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchPlace(),
                  decoration: InputDecoration(
                    labelText: 'Place name',
                    hintText: 'Example: Kodagu, Karnataka',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFFF3F6F1),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: _listening ? 'Stop voice search' : 'Search for a place using your voice',
              hint: 'Say the name of a place, town, district, or landmark',
              child: SizedBox(
                height: 56,
                width: 56,
                child: IconButton.filled(
                  onPressed: _searching ? null : _toggleVoiceSearch,
                  icon: Icon(_listening ? Icons.mic : Icons.mic_none_rounded, size: 27),
                  tooltip: _listening ? 'Stop voice search' : 'Search by voice',
                  style: IconButton.styleFrom(
                    backgroundColor: _listening ? const Color(0xFFD32F2F) : const Color(0xFF2F8F3A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _listening ? 'Listening… say the place name now.' : 'Tip: tap the microphone and say a place name.',
              style: TextStyle(color: _listening ? const Color(0xFFD32F2F) : Colors.black54, fontSize: 11, fontWeight: _listening ? FontWeight.w700 : FontWeight.w400),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Prediction time', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _hourController, keyboardType: TextInputType.number, maxLength: 2, decoration: InputDecoration(labelText: 'Hour', hintText: '18', counterText: '', filled: true, fillColor: const Color(0xFFF3F6F1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            Expanded(child: TextField(controller: _minuteController, keyboardType: TextInputType.number, maxLength: 2, decoration: InputDecoration(labelText: 'Minute', hintText: '30', counterText: '', filled: true, fillColor: const Color(0xFFF3F6F1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
            const SizedBox(width: 10),
            OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded), label: const Text('Picker')),
          ]),
          const SizedBox(height: 6),
          Text('24-hour format • current selection: ${_timeText()}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: _searching ? null : _searchPlace, icon: const Icon(Icons.radar), label: Text(_searching ? 'Finding place...' : 'Find Place & Check Risk', style: const TextStyle(fontWeight: FontWeight.w800)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2F8F3A), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
          const SizedBox(height: 18),
          const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('OR ENTER COORDINATES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black45))), Expanded(child: Divider())]),
          const SizedBox(height: 13),
          Row(children: [
            Expanded(child: TextField(controller: _latController, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: 'Latitude', hintText: '11.93', filled: true, fillColor: const Color(0xFFF3F6F1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _lonController, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: 'Longitude', hintText: '76.13', filled: true, fillColor: const Color(0xFFF3F6F1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _useCoordinates, icon: const Icon(Icons.pin_drop_outlined), label: const Text('Use Coordinates with Selected Time'))),
          const SizedBox(height: 18),
          const Text('Quick locations', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 8, children: _presets.map((p) => ActionChip(label: Text(p['name'].toString()), onPressed: () => _preset(p))).toList()),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(width: double.infinity, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(12)), child: Text(_error, style: const TextStyle(color: Color(0xFFB3261E), fontSize: 12))),
          ],
        ]),
      ),
    );
  }
}
