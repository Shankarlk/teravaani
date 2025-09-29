import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../database/database_helper.dart';

class CropInfoScreen extends StatefulWidget {
  const CropInfoScreen({super.key});

  @override
  State<CropInfoScreen> createState() => _CropInfoScreenState();
}

class _CropInfoScreenState extends State<CropInfoScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  String _languageCode = 'kn';
  bool _isSpeaking = false;
  bool _isPaused = false;

  Set<int> visibleIndexes = {};
  int lastSpokenStartIndex = -1; // store last spoken starting index
  bool autoSpeaking = false; 

  final String kannadaParagraph = '''ಇಲ್ಲಿ ಮೆಕ್ಕೆಜೋಳ ಬೆಳೆಗಾಗಿ ಸರಿಯಾದ ಮತ್ತು ಸುಧಾರಿತ ಕೃಷಿ ಮಾರ್ಗದರ್ಶಿ ಪ್ಯಾರಾಗ್ರಾಫ್ ನೀಡಲಾಗಿದೆ, ಇದರಲ್ಲಿ ಬೀಜ, ರಸಗೊಬ್ಬರ, ಕೀಟನಾಶಕಗಳ ಪ್ರಮಾಣಗಳು, ಕಂಪನಿಗಳ ಹೆಸರು ಮತ್ತು ವೆಚ್ಚದ ವಿವರಗಳಿವೆ:

ಮೆಕ್ಕೆಜೋಳವನ್ನು ಯಶಸ್ವಿಯಾಗಿ ಬೆಳೆಯಲು ಪ್ರತಿ ಎಕರೆಗೆ 8-10 ಕೆ.ಜಿ. Rasi 621 ಬೀಜಗಳನ್ನು ಬಳಸುವುದು ಸೂಕ್ತ. ಬಿತ್ತನೆಗೂ ಮುನ್ನ ಬೀಜಗಳಿಗೆ 5 ಗ್ರಾಂ Bavistin ಕೀಟನಾಶಕ ಮಿಶ್ರಣ ಮಾಡಿ ಉಪಚಾರ ನೀಡಬೇಕು. ನಾವಿಲು ಹುಳ ಹಾಗೂ ಎಲೆ ಕೀಟಗಳ ನಿಯಂತ್ರಣಕ್ಕೆ 300 ಎಂ.ಎಲ್. Confidor ಅಥವಾ 400 ಎಂ.ಎಲ್. Chloropyriphos ಅನ್ನು (ಕಂಪನಿ: Bayer Crop Science) 200 ಲೀಟರ್ ನೀರಿಗೆ ಮಿಶ್ರಣ ಮಾಡಿ ಸಿಂಪಡಿಸಬೇಕು. ಬೆಳೆಯ ಆರಂಭಿಕ ಹಂತದಲ್ಲಿ 50 ಕೆ.ಜಿ. DAP (Diammonium Phosphate) ಮತ್ತು 25 ಕೆ.ಜಿ. MOP (Muriate of Potash) ರಸಗೊಬ್ಬರವನ್ನು ಮಣ್ಣುಗೆ ಹಾಕುವುದು ಫಲಪ್ರದ. 20 ದಿನಗಳ ಬಳಿಕ 25 ಕೆ.ಜಿ. ಯೂರಿಯಾ ಪುನಃ ನೀಡಿ.

ತದನಂತರದ ಬೆಳವಣಿಗೆ ಹಂತಗಳಲ್ಲಿ, ಕೊಳೆತ ಹುಳ ತಡೆಗೆ 200 ಎಂ.ಎಲ್. Spinosad ಅಥವಾ 250 ಎಂ.ಎಲ್. Emamectin Benzoate ಅನ್ನು 150 ಲೀಟರ್ ನೀರಿಗೆ ಮಿಶ್ರಣ ಮಾಡಿ ಸಿಂಪಡಿಸಬಹುದು. ಪ್ರತಿ ಎಕರೆಗೆ 12 ಕೆ.ಜಿ. Pioneer 30V92 ಬೀಜಗಳು ಉತ್ತಮ ಬೆಳೆಯನ್ನು ನೀಡುತ್ತವೆ. ಮಧ್ಯ ಹಂತದಲ್ಲಿ 30 ಕೆ.ಜಿ. NPK ಗೊಬ್ಬರ ಮತ್ತು 20 ಕೆ.ಜಿ. ಯೂರಿಯಾ ಇನ್ನೊಂದು ಬಾರಿ ನೀಡಬೇಕು. ಒಟ್ಟು ಬೆಳೆ ವೆಚ್ಚವು ಸುಮಾರು ₹3850.75 ಆಗಬಹುದು.

ಈ ಸೂಚನೆಗಳು Bayer Crop Science ಮತ್ತು IFFCO ಸಂಸ್ಥೆಗಳ ಸಲಹೆಗಳ ಆಧಾರಿತವಾಗಿದ್ದು, ಸ್ಥಳೀಯ ಹವಾಮಾನ ಹಾಗೂ ಮಣ್ಣಿನ ಗುಣಮಟ್ಟವನ್ನು ಅವಲಂಬಿಸಿರುತ್ತವೆ. ಕೃಷಿ ಇಲಾಖೆಯ ಸಲಹೆಗಳನ್ನು ಅನುಸರಿಸುವುದು ಉತ್ತಮ.''';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _flutterTts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
  }

  Future<void> _loadLanguage() async {
    final settings = await DatabaseHelper().getUserSettings();
    if (settings != null && settings['language'] != null) {
      setState(() => _languageCode = settings['language']);
    }
    await _flutterTts.setLanguage(_languageCode);
  }

  Future<void> _speakVisibleSentences(List<String> allSentences) async {
    if (visibleIndexes.isEmpty) return;

    final visibleText = visibleIndexes.toList()
      ..sort()
      ..removeWhere((index) => index < 0 || index >= allSentences.length);

    final textToRead = visibleText.map((i) => allSentences[i]).join(' ');

    if (textToRead.trim().isNotEmpty) {
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(textToRead);
      setState(() => _isSpeaking = true);
    }
  }

  Future<void> _pause() async {
    await _flutterTts.pause();
    setState(() => _isSpeaking = false);
  }

  Future<void> _togglePlayPause(List<String> sentences) async {
    if (_isSpeaking) {
      await _flutterTts.pause();
      setState(() {
        _isSpeaking = false;
        _isPaused = true;
      });
    } else {
      final visibleText = _getVisibleText(sentences);
      if (visibleText.isNotEmpty) {
        await _speakText(visibleText); // just start speaking again
      }
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    }
  }


  Future<void> _stop() async {
    await _flutterTts.stop();
    setState(() => _isSpeaking = false);
  }

  String _getVisibleText(List<String> sentences) {
    final indexes = visibleIndexes.toList()..sort();
    final visibleText = indexes.map((i) => sentences[i]).join(' ');
    return visibleText.trim();
  }


  @override
  void dispose() {
    _flutterTts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _speakText(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.stop(); // stop any previous
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(text);
      setState(() => _isSpeaking = true);
    }
  }


  @override
  Widget build(BuildContext context) {
    final sentences = kannadaParagraph
        .trim()
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('ಮೆಕ್ಕೆಜೋಳ ಮಾಹಿತಿ')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: sentences.length,
                itemBuilder: (context, index) {
                  final sentence = sentences[index];
                  return VisibilityDetector(
                    key: Key('line_$index'),
                   onVisibilityChanged: (info) {
                    if (info.visibleFraction > 0) {
                      visibleIndexes.add(index);

                      // Check for scroll and auto-speak if index changed
                      if (index < lastSpokenStartIndex || lastSpokenStartIndex == -1) {
                        lastSpokenStartIndex = index;
                        if (autoSpeaking && !_isSpeaking) {
                          final visibleText = _getVisibleText(sentences);
                          _speakText(visibleText);
                        }
                      }
                    } else {
                      visibleIndexes.remove(index);
                    }
                  },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        sentence,
                        style: const TextStyle(fontSize: 18, height: 1.5),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _togglePlayPause(sentences),
                  icon: Icon(_isSpeaking ? Icons.pause : Icons.play_arrow),
                  label: Text(_isSpeaking ? "ವಿರಮಿಸು" : "ಓದಿ"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
