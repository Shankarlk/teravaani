import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:teravaani/screens/CropManagementScreen.dart';
import '../api/pageapi.dart';

class CropEvent {
  final String eventType;
  final String scheduledDate;

  CropEvent({required this.eventType, required this.scheduledDate});

  factory CropEvent.fromJson(Map<String, dynamic> json) {
    return CropEvent(
      eventType: json['eventType'] ?? '',
      scheduledDate: json['scheduledDate'] ?? '',
    );
  }
}

class CalendarScreen extends StatefulWidget {
  final String userId;
  final String targetLangCode;
  final String? cropName;

  const CalendarScreen({
    required this.userId,
    required this.targetLangCode,
    this.cropName,
  });

  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with WidgetsBindingObserver {
  final FlutterTts flutterTts = FlutterTts();
  late OnDeviceTranslator translator;
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<CropEvent> events = [];
  bool _isSpeaking = false;
  bool isLoading = false;
  bool cropAsked = false;
  String? cropName;
  String? errorMessage;
  bool _hasInternet = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
  WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      bool hasInternet = result != ConnectivityResult.none;

      if (!hasInternet && mounted) {
        _showNoInternetDialog();
      }

      setState(() {
        _hasInternet = hasInternet;
      });
    });
    translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _getMLKitLanguage(widget.targetLangCode),
    );
    flutterTts.setLanguage(widget.targetLangCode);
    flutterTts.setSpeechRate(0.5);
    flutterTts.setVolume(1.0);
    flutterTts.setPitch(1.0);

    PageAPI.logPageVisit("CropCalendarScreen");

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.cropName != null && widget.cropName!.isNotEmpty) {
        setState(() {
          cropName = widget.cropName;
          cropAsked = true;
          isLoading = true;
        });
        await _fetchEvents(widget.cropName!);
      } else {
        final msg = await translateToNative("Please say the crop name");
        await flutterTts.speak(msg);
      }
    });
  }

  Future<void> _checkInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    bool hasInternet = connectivityResult != ConnectivityResult.none;

    if (!hasInternet && mounted) {
      _showNoInternetDialog();
    }

    setState(() {
      _hasInternet = hasInternet;
    });
  }

  void _showNoInternetDialog() async {
    final msg = await translateToNative(
      "No Internet Connection. Please check your connection and try again.",
    );
    final almsg = await translateToNative("Alert");
    final okmsg = await translateToNative("OK");

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Alert\n($almsg)"),
          content: Text(
            "No Internet Connection. Please check your connection and try again.\n($msg)",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: Text("OK\n($okmsg)"),
            ),
          ],
        ),
      );
      await flutterTts.speak(msg); // 🔊 Speak the message
    }
  }

  @override
  void dispose() {
    translator.close();
    flutterTts.stop();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is minimized / backgrounded
        flutterTts.stop();
        setState(() => _isSpeaking = false);
    }
  }

  TranslateLanguage _getMLKitLanguage(String code) {
    switch (code) {
      case 'hi':
        return TranslateLanguage.hindi;
      case 'bn':
        return TranslateLanguage.bengali;
      case 'gu':
        return TranslateLanguage.gujarati;
      case 'kn':
        return TranslateLanguage.kannada;
      case 'mr':
        return TranslateLanguage.marathi;
      case 'ta':
        return TranslateLanguage.tamil;
      case 'te':
        return TranslateLanguage.telugu;
      case 'ur':
        return TranslateLanguage.urdu;
      default:
        return TranslateLanguage.english;
    }
  }

  Future<String> translateToNative(String text) async {
    try {
      final t = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(widget.targetLangCode),
      );
      final translated = await t.translateText(text);
      await t.close();
      return translated;
    } catch (_) {
      return text;
    }
  }

  String getSpeechLocale(String langCode) {
    switch (langCode) {
      case 'hi':
        return 'hi-IN';
      case 'kn':
        return 'kn-IN';
      case 'ta':
        return 'ta-IN';
      case 'te':
        return 'te-IN';
      case 'ml':
        return 'ml-IN';
      case 'mr':
        return 'mr-IN';
      case 'bn':
        return 'bn-IN';
      case 'gu':
        return 'gu-IN';
      case 'ur':
        return 'ur-IN';
      default:
        return 'en-IN';
    }
  }

  Future<void> startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      _speech.listen(
        localeId: getSpeechLocale(widget.targetLangCode),
        listenMode: stt.ListenMode.deviceDefault,
        onResult: (result) async {
          if (result.finalResult) {
            _speech.stop();
            final spoken = result.recognizedWords.toLowerCase();
            print("🎤 Spoken crop: $spoken");
            final translated = await translateNativeToEnglish(spoken);

            setState(() {
              cropName = spoken;
              cropAsked = true;
              isLoading = true;
              errorMessage = null;
            });

            await _fetchEvents(translated);
          }
        },
      );
    }
  }

  Future<String> translateNativeToEnglish(String text) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: _getMLKitLanguage(widget.targetLangCode),
        targetLanguage: TranslateLanguage.english,
      );
      final translated = await translator.translateText(text);
      await translator.close();
      return translated;
    } catch (_) {
      return text;
    }
  }

  Future<void> _fetchEvents(String crop) async {
    try {
      final uri = Uri.parse(
        "http://172.20.10.5:3000/api/cropcalendarbyuser?userId=${widget.userId}&cropName=$crop",
      );
      final response = await http.get(uri);
      print("📡 API Response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        print("📡 API Response: $data $crop");

        if (data.isEmpty) {
          final msg = await translateToNative(
            "We Dont have Details of $crop. Please Check other Crops",
          );
          setState(() {
            errorMessage =
                "We Dont have Details of $crop. Please Check other Crops\n ($msg)";
            events.clear();
          });
          await flutterTts.speak(msg);
        } else {
          setState(() {
            events = data.map((e) => CropEvent.fromJson(e)).toList();
          });
        }
      } else {
        final msg = await translateToNative("Failed to fetch crop events.");
        setState(() => errorMessage = msg);
        await flutterTts.speak(msg);
      }
    } catch (e) {
      final msg = await translateToNative(
        "Service unavailable. Please try again later.",
      );
      final almsg = await translateToNative("Alert");
      final okmsg = await translateToNative("ok");

      setState(() => errorMessage = "");
      await flutterTts.speak(msg);

      // 🔹 Show Alert Box
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("Alert\n($almsg)"),
            content: Text(
              "Service unavailable. Please try again later.\n($msg)",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    cropName = null;
                  });
                  Navigator.of(ctx).pop();
                },
                child: Text("OK\n($okmsg)"),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<String> _getVisibleText() async {
    if (events.isEmpty) return "";

    // Translate all event types in parallel
    final translatedEvents = await Future.wait(
      events.map((e) async {
        final nativeText = await translateToNative(e.eventType);
        final date = e.scheduledDate.split("T").first;
        return "$nativeText on $date";
      }).toList(),
    );

    return translatedEvents.join(". ");
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // When back is pressed → go to CropManagementScreen instead of Home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CropManagementScreen(langCode: widget.targetLangCode),
          ),
        );
        return false; // Prevent default pop
      },
      child: Scaffold(
        appBar: AppBar(
          title: FutureBuilder<String>(
            future: translateToNative("Crop Guide"),
            builder: (context, snapshot) {
              final translated = snapshot.data ?? "";
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 📝 Title (English + Native)
                  Expanded(
                    child: Text(
                      "Crop Guide\n($translated)",
                      style: const TextStyle(
                        color: Colors.white, // white text color
                        fontWeight: FontWeight.w700, // bold
                        fontSize: 18,
                      ),
                    ),
                  ),

                  const SizedBox(width: 20),

                  // 🌱 Logo Image
                  Image.asset(
                    "assets/logo.png", // same logo used in other screens
                    height: 70,
                    fit: BoxFit.contain,
                  ),
                ],
              );
            },
          ),
          backgroundColor: Colors.green,
          iconTheme: const IconThemeData(
            color: Colors.white, // back button color
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔹 Prompt + Crop Name inside card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FutureBuilder<String>(
                              future: translateToNative(
                                "Please say the crop name",
                              ),
                              builder: (context, snapshot) {
                                return Text(
                                  "Please say the crop name\n(${snapshot.data ?? ''})",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                cropName ?? "",
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🔹 Events / Steps list
                    Expanded(
                      child: events.isEmpty
                          ? Center(
                              child: Text(
                                errorMessage ?? "",
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : FutureBuilder<List<String>>(
                              future: Future.wait(
                                events
                                    .map((e) => translateToNative(e.eventType))
                                    .toList(),
                              ),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final translatedEvents = snapshot.data!;
                                return ListView.builder(
                                  padding: const EdgeInsets.all(0),
                                  itemCount: events.length,
                                  itemBuilder: (context, index) {
                                    final e = events[index];
                                    final nativeEvent = translatedEvents[index];
                                    return Card(
                                      elevation: 2,
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                "${e.eventType}\n($nativeEvent)",
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              e.scheduledDate.split("T").first,
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 10.0, right: 16.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (events.isNotEmpty)
                FloatingActionButton(
                  heroTag: "speakBtn",
                  onPressed: () async {
                    if (_isSpeaking) {
                      await flutterTts.stop();
                      setState(() => _isSpeaking = false);
                    } else {
                      final text = await _getVisibleText();
                      if (text.isNotEmpty) {
                        setState(() => _isSpeaking = true);
                        await flutterTts.speak(text);
                        flutterTts.setCompletionHandler(() {
                          setState(() => _isSpeaking = false);
                        });
                      }
                    }
                  },
                  backgroundColor: _isSpeaking ? Colors.grey : Colors.blue,
                  child: Icon(
                    _isSpeaking ? Icons.pause : Icons.volume_up,
                    size: 28,
                  ),
                ),
              const SizedBox(width: 12), // space between buttons
              FloatingActionButton(
                heroTag: "micBtn",
                onPressed: () async {
                  setState(() {}); // Refresh icon/color
                  await startListening();
                },
                backgroundColor: _speech.isListening
                    ? Colors.red
                    : Colors.green,
                child: Icon(
                  _speech.isListening ? Icons.mic : Icons.mic_off,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
