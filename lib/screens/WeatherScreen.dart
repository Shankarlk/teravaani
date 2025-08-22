import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../api/pageapi.dart';

class WeatherScreen extends StatefulWidget {
  final List<String> forecastDisplay;
  final List<String> forecastSpeak;

  
  const WeatherScreen({
    super.key,
    required this.forecastDisplay,
    required this.forecastSpeak,
  });

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
    PageAPI.logPageVisit("WeatherScreen");
  }

Future<void> _toggleSpeech() async {
  if (_isSpeaking) {
    await _flutterTts.pause();
    setState(() => _isSpeaking = false);
  } else {
    final nativeText = widget.forecastSpeak.join('. ');
    if (nativeText.trim().isNotEmpty) {
      await _flutterTts.setLanguage("kn-IN");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(nativeText);
      setState(() => _isSpeaking = true);
    }
  }
}

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('7-Day Forecast'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: widget.forecastDisplay.isEmpty
            ? const Center(child: Text('No forecast available'))
            : ListView.builder(
               itemCount: widget.forecastDisplay.length,
itemBuilder: (context, index) {
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.forecastDisplay[index].substring(0, 2), // icon
            style: const TextStyle(fontSize: 25),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.forecastDisplay[index].substring(2).trim(),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    ),
  );
},
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleSpeech,
        backgroundColor: Colors.grey,
        child: Icon(_isSpeaking ? Icons.pause : Icons.volume_up),
        tooltip: _isSpeaking ? "Pause" : "Speak forecast",
      ),
    );
  }
}
