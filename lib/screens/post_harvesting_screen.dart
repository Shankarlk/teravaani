import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'dart:async'; // Import for Timer
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teravaani/screens/CropManagementScreen.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/pageapi.dart';

class PostHarvestingScreen extends StatefulWidget {
  final String langCode;

  const PostHarvestingScreen({Key? key, required this.langCode})
    : super(key: key);

  @override
  State<PostHarvestingScreen> createState() => _PostHarvestingScreenState();
}

class _PostHarvestingScreenState extends State<PostHarvestingScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool isListening = false;
  String? cropName;
  String? sowingDate;
  String currentPrompt = "Please say the crop name";
  bool waitingForCrop = true;
  bool waitingForDate = false;
  String? responseMessage;
  String? errorMessage; // To show validation errors
  bool hasValidationError = false; // For styling red color
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _hasInternet = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
     _connectivitySubscription =
      Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
    bool hasInternet = result != ConnectivityResult.none;

    if (!hasInternet && mounted) {
      _showNoInternetDialog();
    }

    setState(() {
      _hasInternet = hasInternet;
    });
  });
    _initTts();
    _initializeLocalNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final nativePrompt = await translateToNative(currentPrompt);
      await speak(nativePrompt);
    });
    _checkAndShowReminders();
    PageAPI.logPageVisit("PostHarvestingScreen");
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
    "No Internet Connection. Please check your connection and try again."
  );
  final almsg = await translateToNative("Alert");
  final okmsg = await translateToNative("OK");

  if (mounted) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Alert\n($almsg)"),
        content: Text("No Internet Connection. Please check your connection and try again.\n($msg)"),
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
    _speech.stop(); // Ensure speech recognizer is stopped
    _speech.cancel(); // Cancel any pending operations
    flutterTts.stop(); // Stop any ongoing speech
    super.dispose();
  }

  Future<void> speak(String text) async {
    await flutterTts.speak(text);
  }

  Future<void> _checkAndShowReminders() async {
    final userId = await getOrCreateDeviceId();
    final events = await fetchUpcomingEvents(userId);
    final today = DateTime.now();

    for (final event in events) {
      final eventDate = DateTime.parse(event['ScheduledDate']);
      final diff = eventDate.difference(today).inDays;

      if (diff == 2 || diff == 1 || diff == 0) {
        final formattedDate = DateFormat('d MMMM yyyy').format(eventDate);

        // Translate labels and values
        final eventLabelNative = await translateToNative("Event");
        final dateLabelNative = await translateToNative("Date");
        final eventTypeNative = await translateToNative(event['EventType']);
        final formattedDateNt = await translateToNative(formattedDate);

        final alertTitleNative = await translateToNative("Upcoming Event");
        final okTextNative = await translateToNative("OK");

        final messageNative =
            "🧾 $eventLabelNative: $eventTypeNative\n📅 $dateLabelNative: $formattedDate";

        // 🔊 Speak in native language
        await flutterTts.speak(messageNative);

        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              'event_channel_id',
              'Event Reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            );
        print("shotification");

        const NotificationDetails notificationDetails = NotificationDetails(
          android: androidDetails,
        );
        final int notificationId =
            (event['ID'] ??
                DateTime.now().second * 1000 + DateTime.now().millisecond) %
            100000;
        await flutterLocalNotificationsPlugin.show(
          notificationId, // Unique ID for the notification
          alertTitleNative, // Title
          messageNative, // Body
          notificationDetails,
        );

        // ✅ Mark reminder sent after showing the notification
        await markReminderSent(event['ID']);
        break;
        // showDialog(
        //   context: context,
        //   builder: (_) => AlertDialog(
        //     title: Text("Upcoming Event\n($alertTitleNative)"),
        //     content: Text(
        //       "🧾 Event: ${event['EventType']} \n( $eventLabelNative: $eventTypeNative)\n"
        //       "📅 Date: $formattedDate \n ($dateLabelNative: $formattedDateNt)",
        //     ),
        //     actions: [
        //       TextButton(
        //         onPressed: () async {
        //           Navigator.of(context).pop();
        //           await markReminderSent(event['ID']);
        //         },
        //         child: Text("OK ($okTextNative)"),
        //       ),
        //     ],
        //   ),
        // );
        // break;
      }
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidInit,
    );

    await flutterLocalNotificationsPlugin.initialize(settings);
  }

  Future<List<Map<String, dynamic>>> fetchUpcomingEvents(String userId) async {
    final url = Uri.parse(
      "http://172.20.10.5:3000/api/upcoming-events/$userId",
    );

    final response = await http.get(url);
    print("response ${response.body}");
    print("response statusCode ${response.statusCode}");

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);

      if (data['success'] == true && data['events'] is List) {
        return List<Map<String, dynamic>>.from(data['events']);
      } else {
        throw Exception("API format unexpected");
      }
    } else {
      throw Exception("Failed to fetch upcoming events");
    }
  }

  Future<void> markReminderSent(int calendarId) async {
    final url = Uri.parse("http://172.20.10.5:3000/api/mark-reminder-sent");

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({"calendarId": calendarId}),
    );

    if (response.statusCode != 200) {
      print("⚠️ Failed to mark reminder sent for ID $calendarId");
    }
  }

  Future<void> startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => isListening = true);
      _speech.listen(
        localeId: getSpeechLocale(widget.langCode),
        onResult: (result) async {
          if (result.finalResult) {
            _speech.stop();
            setState(() => isListening = false);

            String spokenText = result.recognizedWords.toLowerCase();
            String translatedToEnglish = await translateNativeToEnglish(
              spokenText,
            );
            print(
              "👂 User said (native): $spokenText ➜ (english): $translatedToEnglish",
            );

            if (waitingForCrop) {
              if (translatedToEnglish.trim().toLowerCase() != "tomato") {
                final error = await translateToNative(
                  "Only 'tomato' crop is supported currently",
                );
                setState(() {
                  errorMessage = error;
                  hasValidationError = true;
                });
                await flutterTts.speak(error);
                return; // 🚫 don't proceed
              }

              cropName = spokenText; // Save original native text
              setState(() {
                errorMessage = null;
                hasValidationError = false;
                currentPrompt = "Please say the sowing date";
                waitingForCrop = false;
                waitingForDate = true;
              });
              final currentPromptnt = await translateToNative(
                "Please say the sowing date",
              );
              await speak(currentPromptnt);
            } else if (waitingForDate) {
              String translatedDate = translatedToEnglish;
              try {
                DateFormat('d MMMM yyyy').parse(translatedDate);
                sowingDate = spokenText;
                setState(() {
                  errorMessage = null;
                  hasValidationError = false;
                  waitingForDate = false;
                });
                await sendDataToApi(); // ✅ all validated, go ahead
              } catch (_) {
                final error = await translateToNative(
                  "Invalid date. Please say a valid date like 25 July 2025.",
                );
                setState(() {
                  errorMessage = error;
                  hasValidationError = true;
                });
                await flutterTts.speak(error);
                return;
              }
            }
          }
        },
      );
    }
  }

  // Helper to get SpeechToText locale ID from custom language codes
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
        return 'ml-IN'; // Malayalam added for completeness if supported
      case 'mr':
        return 'mr-IN';
      case 'bn':
        return 'bn-IN';
      case 'gu':
        return 'gu-IN';
      case 'ur':
        return 'ur-IN';
      default:
        return 'en-IN'; // Default to Indian English
    }
  }

  Future<String> translateToNative(String text) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(widget.langCode),
      );
      final translated = await translator.translateText(text);
      await translator.close(); // Close translator to release resources
      return translated;
    } catch (e) {
      print("❌ Translation to native failed: $e");
      return text; // Return original text on failure
    }
  }

  // Translates native text back to English for query processing
  Future<String> translateNativeToEnglish(String nativeText) async {
    try {
      final modelManager = OnDeviceTranslatorModelManager();
      // Ensure the English model is downloaded for translation to English
      final isEnglishModelDownloaded = await modelManager.isModelDownloaded(
        'en',
      );
      if (!isEnglishModelDownloaded) {
        print("Downloading English translation model...");
        await modelManager.downloadModel('en', isWifiRequired: false);
      }

      final translator = OnDeviceTranslator(
        sourceLanguage: _getMLKitLanguage(widget.langCode),
        targetLanguage: TranslateLanguage.english,
      );
      final translatedText = await translator.translateText(nativeText);
      await translator.close();
      return translatedText;
    } catch (e) {
      print("❌ Native ➜ English translation failed: $e");
      return nativeText; // Return original text on failure
    }
  }

  Future<void> _initTts() async {
    // Set TTS language, rate, and pitch for natural speech
    print('_currentLangCode: ${widget.langCode}');
    await flutterTts.setLanguage(widget.langCode);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
  }

  TranslateLanguage _getMLKitLanguage(String langCode) {
    switch (langCode) {
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
        return TranslateLanguage.english; // Default to English
    }
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      deviceId = const Uuid().v4(); // Generate UUID
      await prefs.setString('device_id', deviceId);
    }

    return deviceId;
  }

  Future<void> sendDataToApi() async {
    try {
      print('CropName: $cropName and sowingDate: $sowingDate');
      String cropNameEng = await translateNativeToEnglish(cropName ?? '');
      String sowingDateENg = await translateNativeToEnglish(sowingDate ?? '');
      DateTime parsedDate = DateFormat('d MMMM yyyy').parse(sowingDateENg!);
      String formattedDate = DateFormat('yyyy-MM-dd').format(parsedDate);
      final userid = await getOrCreateDeviceId();

      final url = Uri.parse("http://172.20.10.5:3000/api/generate-calendar");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "userId": userid,
          "cropName": cropNameEng,
          "sowingDate": formattedDate,
          "noOfPlants": 0,
        }),
      );

      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        String responseMessageNt = await translateToNative(
          responseData["message"],
        );
        setState(() => responseMessage = responseMessageNt);
        await flutterTts.speak(responseMessageNt);
      } else {
        await flutterTts.speak("There was an error submitting the data");
      }
    } catch (e) {
      print("Error: $e");
      String responseMessageNt = await translateToNative(
        "Service unavailable. Please try again later.",
      );
      final almsg = await translateToNative("Alert");
      final okmsg = await translateToNative("ok");
      setState(() {
        responseMessage = null;
      });
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("Alert\n($almsg)"),
            content: Text(
              "Service unavailable. Please try again later.\n($responseMessageNt)",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    cropName = null;
                    sowingDate = null;
                  });
                  Navigator.of(ctx).pop();
                },
                child: Text("OK\n($okmsg)"),
              ),
            ],
          ),
        );
        await flutterTts.speak(responseMessageNt);
      }
      // setState(() => responseMessage = responseMessageNt);
      // await flutterTts.speak(responseMessageNt);
      // if (e == "Connection timed out") {
      // } else {
      //   String responseMessageNt = await translateToNative(
      //     "Failed To Save the Events",
      //   );
      //   setState(() => responseMessage = responseMessageNt);
      //   await flutterTts.speak(responseMessageNt);
      // }
    }
  }

  Widget _buildField(String label, String value) {
    return FutureBuilder<String>(
      future: translateToNative(label),
      builder: (context, snapshot) {
        String translated = snapshot.data ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$label\n($translated)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(value.isEmpty ? '-' : value),
            ),
            SizedBox(height: 20),
          ],
        );
      },
    );
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
                CropManagementScreen(langCode: widget.langCode),
          ),
        );
        return false; // Prevent default pop
      },
      child: Scaffold(
        appBar: AppBar(
          title: FutureBuilder<String>(
            future: translateToNative("Post Harvesting"),
            builder: (context, snapshot) {
              final translated = snapshot.data ?? "Post Harvesting";
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 📝 Title (English + Native)
                  Expanded(
                    child: Text(
                      "Post Harvesting\n($translated)",
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
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 Prompt + Fields inside card
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
                        future: translateToNative(currentPrompt),
                        builder: (context, snapshot) {
                          return Text(
                            "$currentPrompt\n(${snapshot.data ?? ''})",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildField("Crop Name", cropName ?? ""),
                      _buildField("Sowing Date", sowingDate ?? ""),
                      if (responseMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          responseMessage!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (hasValidationError && errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            if (isListening) {
              _speech.stop();
              setState(() => isListening = false);
            } else {
              startListening();
            }
          },
          backgroundColor: isListening ? Colors.red : Colors.green,
          child: Icon(isListening ? Icons.mic : Icons.mic_off, size: 30),
          tooltip: isListening ? "Stop Listening" : "Start Listening",
        ),
      ),
    );
  }
}
