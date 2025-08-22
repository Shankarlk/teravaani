import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter_tts/flutter_tts.dart'; 
import '../api/pageapi.dart';

class CropEvent {
  final String eventType;
  final String scheduledDate;

  CropEvent({
    required this.eventType,
    required this.scheduledDate,
  });

  factory CropEvent.fromJson(Map<String, dynamic> json) {
    return CropEvent(
      eventType: json['EventType'] ?? '',
      scheduledDate: json['ScheduledDate'] ?? '',
    );
  }
}

class CalendarScreen extends StatefulWidget {
  final String userId;
  final String targetLangCode;

  const CalendarScreen({required this.userId, required this.targetLangCode});

  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late OnDeviceTranslator translator;
  final FlutterTts flutterTts = FlutterTts();
  List<CropEvent> events = [];
  bool _isSpeaking = false;
bool _isPaused = false;

  final ScrollController _scrollController = ScrollController();
final Set<int> visibleRowIndexes = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _getTranslateLang(widget.targetLangCode),
    );
  flutterTts.setLanguage(widget.targetLangCode); // ✅ set once
  flutterTts.setSpeechRate(0.5);
  flutterTts.setVolume(1.0);
  flutterTts.setPitch(1.0);
  flutterTts.awaitSpeakCompletion(true);
  _scrollController.addListener(_trackVisibleRows);
flutterTts.setCompletionHandler(() {
  setState(() {
    _isSpeaking = false;
    _isPaused = false;
  });
});

flutterTts.setPauseHandler(() {
  setState(() {
    _isSpeaking = false;
    _isPaused = true;
  });
});

flutterTts.setContinueHandler(() {
  setState(() {
    _isSpeaking = true;
    _isPaused = false;
  });
});

flutterTts.setCancelHandler(() {
  setState(() {
    _isSpeaking = false;
    _isPaused = false;
  });
});

    _fetchEvents();
  PageAPI.logPageVisit("ViewCropCalendarScreen");
  }
  @override
void dispose() {
  translator.close();
  flutterTts.stop(); // <-- good practice
  super.dispose();
}


    Future<String> translateToNative(String text) async {
        try {
        final translator = OnDeviceTranslator(
            sourceLanguage: TranslateLanguage.english,
            targetLanguage: _getMLKitLanguage(widget.targetLangCode),
        );
        final translated = await translator.translateText(text);
        await translator.close(); // Close translator to release resources
        return translated;
        } catch (e) {
        print("❌ Translation to native failed: $e");
        return text; // Return original text on failure
        }
    }
    TranslateLanguage _getMLKitLanguage(String langCode) {
        switch (langCode) {
        case 'hi': return TranslateLanguage.hindi;
        case 'bn': return TranslateLanguage.bengali;
        case 'gu': return TranslateLanguage.gujarati;
        case 'kn': return TranslateLanguage.kannada;
        case 'mr': return TranslateLanguage.marathi;
        case 'ta': return TranslateLanguage.tamil;
        case 'te': return TranslateLanguage.telugu;
        case 'ur': return TranslateLanguage.urdu;
        default: return TranslateLanguage.english; // Default to English
        }
    }
void _trackVisibleRows() {
  // If using `itemExtent`, you can calculate visible range from scroll offset
  final itemHeight = 70.0; // Set your row height
  final firstVisible = (_scrollController.offset / itemHeight).floor();
  final visibleCount = (MediaQuery.of(context).size.height / itemHeight).ceil();
  final lastVisible = firstVisible + visibleCount;

  visibleRowIndexes
    ..clear()
    ..addAll(List.generate(visibleCount, (i) => i + firstVisible).where((i) => i < events.length));
}

  TranslateLanguage _getTranslateLang(String code) {
    switch (code) {
      case 'hi': return TranslateLanguage.hindi;
      case 'kn': return TranslateLanguage.kannada;
      case 'te': return TranslateLanguage.telugu;
      case 'ta': return TranslateLanguage.tamil;
      case 'mr': return TranslateLanguage.marathi;
      default: return TranslateLanguage.hindi;
    }
  }

  Future<void> _fetchEvents() async {
    try {
      final uri = Uri.parse("http://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/api/cropcalendarbyuser?userId=${widget.userId}");
      final response = await http.get(uri);
      print('response:- ${response.body} and ${response.statusCode} and userid = ${widget.userId}');
      final List data = jsonDecode(response.body);
      final fetchedEvents = data.map((e) => CropEvent.fromJson(e)).toList();

      setState(() => events = List<CropEvent>.from(fetchedEvents));
      
        WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(Duration(milliseconds: 300)); // 🟡 ADD SMALL DELAY
        _trackVisibleRows();
        await _speakVisibleEvents(); // ✅ ensure it's awaited
        });
    } catch (e) {
      print('Error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<String> _translateText(String text) async {
    try {
      return await translator.translateText(text);
    } catch (e) {
      return '';
    }
  }

Future<void> _speakVisibleEvents() async {
  final List<String> sentences = [];

  final indexesToRead = visibleRowIndexes.isEmpty
      ? List.generate(events.length, (i) => i)
      : visibleRowIndexes.toList()..sort();

  for (var i in indexesToRead) {
    final event = events[i];
    final eventName = event.eventType;
    final eventDate = event.scheduledDate.split('T').first;

    final translatedEventName = await translateToNative("$eventName on $eventDate.");
    sentences.add(translatedEventName);
  }

  final textToRead = sentences.join(' ');
  print("Final text to read: $textToRead");

  if (textToRead.trim().isNotEmpty) {
    setState(() {
      _isSpeaking = true;
      _isPaused = false;
    });
    await flutterTts.stop();
    await flutterTts.setLanguage(widget.targetLangCode);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);

    await flutterTts.speak(textToRead);

    setState(() {
      _isSpeaking = true;
      _isPaused = false;
    });
  } else {
    print("Text to read is empty");
  }
}


@override
Widget build(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) => _trackVisibleRows());
    
  return Scaffold(
    appBar: AppBar(title:  FutureBuilder<String>(
    future: translateToNative("crop calendar"),
    builder: (context, snapshot) {
      final translated = snapshot.data ?? "";
      return Text("Crop Calendar\n($translated)");
    },
  ),),
    body: isLoading
        ? Center(child: CircularProgressIndicator())
        : events.isEmpty
            ? FutureBuilder<String>(
      future: translateToNative("No crop operations found."),
      builder: (context, snapshot) {
        final native = snapshot.data ?? "";
        return Center(
          child: Text(
            "No crop operations found.\n($native)",
            textAlign: TextAlign.center,
          ),
        );
      },
    )
            : Column(
                children: [
                  // 🔲 Header Row
                  Container(
                    color: Colors.grey.shade300,
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: FutureBuilder<String>(
  future: translateToNative("operations"),
  builder: (context, snapshot) {
    final translated = snapshot.data ?? "";
    return Text(
      "operations\n($translated)",
      style: TextStyle(fontWeight: FontWeight.bold),
    );
  },
),

                        ),
                        Expanded(
                          flex: 2,
                          child: FutureBuilder<String>(
  future: translateToNative("Date"),
  builder: (context, snapshot) {
    final translated = snapshot.data ?? "";
    return Text(
      "Date\n($translated)",
      style: TextStyle(fontWeight: FontWeight.bold),
    );
  },
),

                        ),
                      ],
                    ),
                  ),

                  Expanded(
  child: ListView.builder(
    controller: _scrollController,
    itemCount: events.length,
    itemBuilder: (context, index) {
      final event = events[index];
      return VisibilityDetector(
        key: Key('row-$index'),
        onVisibilityChanged: (visibilityInfo) {
          if (visibilityInfo.visibleFraction > 0.3) {
            visibleRowIndexes.add(index);
          } else {
            visibleRowIndexes.remove(index);
          }
        },
        child: FutureBuilder<String>(
          future: _translateText(event.eventType),
          builder: (context, snapshot) {
            final translated = snapshot.data ?? '';
            return Container(
              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Text(
                      "${event.eventType}\n(${translated})",
                      style: TextStyle(height: 1.4),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(event.scheduledDate.split('T').first),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  ),
),

                ],
              ),
floatingActionButton: FloatingActionButton(
  onPressed: () async {
    print("Speaker tapped");

    if (_isSpeaking) {
      print("Pausing speech");
      setState(() {
        _isSpeaking = false;
        _isPaused = true;
      });
      await flutterTts.pause();
      setState(() {
        _isSpeaking = false;
        _isPaused = true;
      });
    } else {
      final List<String> sentences = [];

      final indexesToRead = visibleRowIndexes.isEmpty
          ? List.generate(events.length, (i) => i)
          : visibleRowIndexes.toList()..sort();

      for (var i in indexesToRead) {
        final event = events[i];
        final eventName = event.eventType;
        final eventDate = event.scheduledDate.split('T').first;

        final translatedEventName = await translateToNative("$eventName on  $eventDate." );
        //final sentence = "($translatedEventName) $eventDate.";
        //final translated = await translateToNative(translatedEventName);

        print("Adding sentence: $translatedEventName");
        sentences.add(translatedEventName);
      }

      final textToRead = sentences.join(' ');
      print("Final text to read: $textToRead");

      if (textToRead.trim().isNotEmpty) {
        setState(() {
          _isSpeaking = true;
          _isPaused = false;
        });
        await flutterTts.stop(); // reset any previous state

        await flutterTts.setLanguage(widget.targetLangCode); // or your targetLangCode
        await flutterTts.setSpeechRate(0.5);
        await flutterTts.setVolume(1.0);
        await flutterTts.setPitch(1.0);

        await flutterTts.speak(textToRead);

      } else {
        print("Text to read is empty");
      }
    }
  },
  backgroundColor: Colors.grey,
  child: Icon(_isSpeaking ? Icons.pause : Icons.volume_up),
),
  );
}

}
