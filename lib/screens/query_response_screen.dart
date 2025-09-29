import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teravaani/screens/CropManagementScreen.dart';
import 'package:teravaani/screens/WeatherScreen.dart';
import 'package:teravaani/screens/calendar_screen.dart';
import 'package:teravaani/screens/crop_preparation_screen.dart';
import 'package:teravaani/screens/diagnosisScreen.dart';
import 'package:teravaani/screens/market_price_screen.dart';
import 'package:teravaani/screens/post_harvesting_screen.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'dart:async'; // Import for Timer
import '../api/pageapi.dart';
import 'package:url_launcher/url_launcher.dart';

// --- API Configuration ---
// IMPORTANT: For Android Emulator, use '10.0.2.2' to access 'localhost' on your host machine.
// For physical devices, use your computer's actual IP address (e.g., '192.168.1.X').
const String _apiBaseUrl = 'http://172.20.10.5:3000/api';

// Enum for managing chat flow states
enum ChatState {
  initial, // Ready for a new query
  listeningQuery, // User is currently speaking their initial query
  awaitingConfirmation, // Confirmation message displayed, listening for Yes/No
  queryConfirmed, // Query confirmed, processing
  responseDisplayed, // Response displayed
  exiting, // System is ending a flow
}

// Data Model for a Chat Message
class ChatMessage {
  final String englishText;
  final String nativeText;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.englishText,
    required this.nativeText,
    required this.isUser,
    required this.timestamp,
  });
}

// Data Model for Crop (matches your SQL table structure)
class Crop {
  final int cropID;
  final String cropName;
  final String variety;
  final String plantType;
  final String? imageUrl;
  final String? region;

  Crop({
    required this.cropID,
    required this.cropName,
    required this.variety,
    required this.plantType,
    this.imageUrl,
    this.region,
  });

  factory Crop.fromJson(Map<String, dynamic> json) {
    return Crop(
      cropID: json['CropID'],
      cropName: json['CropName'],
      variety: json['Variety'],
      plantType: json['PlantType'],
      imageUrl: json['ImageURL'],
      region: json['Region'],
    );
  }
}

class QueryResponseScreen extends StatefulWidget {
  final String initialLangCode;

  const QueryResponseScreen({Key? key, required this.initialLangCode})
    : super(key: key);

  @override
  _QueryResponseScreenState createState() => _QueryResponseScreenState();
}

class _QueryResponseScreenState extends State<QueryResponseScreen>
    with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;
  late FlutterTts flutterTts;

  bool _isSending = false;
  ChatState _chatState = ChatState.initial;

  // This timer now handles both 10s query silence and 15s confirmation silence
  Timer? _speechActivityTimer;
  String _lastRecognizedWords = ''; // Stores the query for confirmation
  String _query = '';
  String? _pendingCropName;
  String? _presowingCropName;
  String? _diagnosis;
  String? _market;
  String? _weather;
  String? _cropmng;
  String? _postharvest;

  late String _currentLangCode;
  bool _isMicEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      this,
    ); // Add observer for lifecycle events
    _currentLangCode = widget.initialLangCode;

    //await DatabaseHelper().db;
    flutterTts = FlutterTts();
    _initTts();

    _speech = stt.SpeechToText();
    _initSpeechRecognizer();

    _addInitialWelcomeMessage();
    PageAPI.logPageVisit("ChatBotScreen");
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove observer
    _textController.dispose();
    _scrollController.dispose();
    _speech.stop(); // Ensure speech recognizer is stopped
    _speech.cancel(); // Cancel any pending operations
    flutterTts.stop(); // Stop any ongoing speech
    _speechActivityTimer?.cancel(); // Cancel any active timers
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("AppLifecycleState: $state");
    // When the app goes to the background or is detached, stop speech recognition
    if (state == AppLifecycleState.paused) {
      if (_isListening) {
        _speech.stop();
        setState(() {
          _isListening = false;
        });
        print("Mic paused due to app lifecycle state (paused).");
      }
    } else if (state == AppLifecycleState.detached) {
      _speech.stop();
      _speech.cancel();
      flutterTts.stop();
      _speechActivityTimer?.cancel();
      print("Mic stopped and resources disposed due to app being detached.");
    }
  }

  Future<void> _initTts() async {
    // Set TTS language, rate, and pitch for natural speech
    print('_currentLangCode: ${_currentLangCode}');
    await flutterTts.setLanguage(_currentLangCode);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _initSpeechRecognizer() async {
    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      print("Microphone permission not granted for QueryResponseScreen.");
      return; // Cannot proceed without permission
    }

    // Initialize speech recognition
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        print(
          "Speech status (QR): $status (isListening: $_isListening, chatState: $_chatState)",
        );
        if (status == 'notListening' && _isListening) {
          // The speech recognizer has stopped, and our app thought it was listening
          print(
            "DEBUG: onStatus: notListening received and _isListening was true. Setting _isListening to FALSE.",
          );
          setState(() {
            _isListening = false; // Update UI: mic button turns grey
          });
          _speechActivityTimer?.cancel(); // Cancel any active timer

          if (_chatState == ChatState.listeningQuery) {
            if (_textController.text.isNotEmpty) {
              _lastRecognizedWords =
                  _textController.text; // Store the final recognized query
              _query = _textController.text; // Store the final recognized query

              // Add the user message BEFORE confirmation prompt
              setState(() {
                _messages.add(
                  ChatMessage(
                    englishText:
                        _lastRecognizedWords, // Use the recognized words as English text
                    nativeText:
                        _lastRecognizedWords, // Use the recognized words as native text
                    isUser: true,
                    timestamp: DateTime.now(),
                  ),
                );
              });
              _scrollToBottom();
              _textController
                  .clear(); // Clear the text box immediately after adding user message

              // Ask for confirmation AFTER showing user message and clearing text box
              _askForConfirmation(_lastRecognizedWords);
            } else {
              // Mic stopped, but no voice was recognized for the initial query
              _speakText("Sorry, I didn't catch that. Please try again.");
              setState(() {
                _chatState = ChatState.initial; // Reset to initial state
              });
              _textController.clear();
              _addInitialWelcomeMessage(); // Re-add the welcome message
            }
          } else if (_chatState == ChatState.awaitingConfirmation) {
            if (_speechActivityTimer == null ||
                !_speechActivityTimer!.isActive) {
              print(
                "DEBUG: Mic stopped during confirmation (not by timeout), re-prompting.",
              );
              _speakText("Please give the confirmation. Say 'Yes' or 'No'.");
              //_startListeningForConfirmation(); // Restart listening for confirmation
            }
          }
        } else if (status == 'listening') {
          print(
            "DEBUG: onStatus: listening received. Setting _isListening to TRUE.",
          );
          setState(() {
            _isListening = true; // Update UI: mic button turns red
          });
          print("Successfully listening (QR).");
        }
      },
      onError: (error) {
        // Handle any errors from speech recognition
        print("Speech error (QR): $error");
        setState(() {
          _isListening = false; // Turn off mic UI
          _chatState = ChatState.initial; // Reset state on error
        });
        _isListening = false; // Turn off mic UI
        _chatState = ChatState.initial; // Reset state on error
        _speechActivityTimer?.cancel(); // Cancel any active timers
        _speakText(
          "An error occurred with speech recognition. Please try again.",
        );
        _textController.clear();
        _addInitialWelcomeMessage(); // Re-add the welcome message
      },
    );
    print("Speech recognizer initialized (QR): $_speechAvailable");
  }

  Future<void> _addInitialWelcomeMessage() async {
    final welcomeEnglish = "Hello! How can I help you today?";
    final welcomeNative = await translateToNative(welcomeEnglish);
    setState(() {
      _messages.add(
        ChatMessage(
          englishText: welcomeEnglish,
          nativeText: welcomeNative,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
      _chatState = ChatState.initial; // Ensure state is initial
    });
    _speakText(welcomeNative); // Speak the welcome message
    _scrollToBottom(); // Scroll to the latest message
  }

  // Helper to get MLKit TranslateLanguage from custom language codes
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

  // Translates English text to the user's selected native language
  Future<String> translateToNative(String text) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(_currentLangCode),
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
        sourceLanguage: _getMLKitLanguage(_currentLangCode),
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

  bool _hasUserSpoken = false;
  void _startListening() async {
    // ✅ Check microphone permission
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        print("Microphone permission not granted.");
        _speakText("Microphone permission is required to use voice input.");
        return;
      }
    }

    if (_speechAvailable && !_speech.isListening) {
      setState(() {
        _isListening = true;
        _textController.clear();
        _lastRecognizedWords = '';
      });
      print("🎤 Mic started. Listening...");

      bool userSpoke = false;

      _speech.listen(
        localeId: getSpeechLocale(_currentLangCode),
        listenMode: stt.ListenMode.dictation,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        onResult: (result) async {
          if (result.recognizedWords.trim().isNotEmpty) {
            userSpoke = true;
            setState(() {
              _textController.text = result.recognizedWords;
            });

            // Cancel any previous timers
            _speechActivityTimer?.cancel();

            // Timer for 5-second silence detection
            _speechActivityTimer = Timer(const Duration(seconds: 5), () async {
              if (_isListening &&
                  _chatState != ChatState.awaitingConfirmation) {
                _stopListening();

                if (_textController.text.isNotEmpty) {
                  _lastRecognizedWords = _textController.text;
                  _query = _textController.text;

                  // Add user's message
                  setState(() {
                    _messages.add(
                      ChatMessage(
                        englishText: _lastRecognizedWords,
                        nativeText: _lastRecognizedWords,
                        isUser: true,
                        timestamp: DateTime.now(),
                      ),
                    );
                  });
                  _scrollToBottom();
                  _textController.clear();
                  final engtest = await translateNativeToEnglish(
                    _lastRecognizedWords,
                  );

                  // ---------- CROP SCHEDULE DETECTION ----------
                  String? cropName = extractCropName(engtest.toLowerCase());

                  if (engtest.toLowerCase().contains("crop guide") || engtest.toLowerCase().contains("guide")||
                      engtest.toLowerCase().contains("schedule")) {
                    // Ask for confirmation before showing schedule
                    setState(() {
                      _isListening = false;
                    });
                    final id = await getOrCreateDeviceId();
                    _pendingCropName = cropName;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CalendarScreen(
                          userId: id,
                          targetLangCode: _currentLangCode,
                          cropName: _pendingCropName,
                        ),
                      ),
                    );
                    // setState(() {
                    //   _chatState = ChatState.awaitingConfirmation;
                    // });
                    // final confirmationMsg =
                    //     "Do you want to see the schedule for $cropName? Say 'Yes' or 'No'.";
                    // final translatedMsg = await translateToNative(
                    //   confirmationMsg,
                    // );
                    // setState(() {
                    //   _isListening = false;
                    //   _messages.add(
                    //     ChatMessage(
                    //       englishText: confirmationMsg,
                    //       nativeText: translatedMsg,
                    //       isUser: false,
                    //       timestamp: DateTime.now(),
                    //     ),
                    //   );
                    // });
                    // _speakText(translatedMsg);
                    _scrollToBottom();
                  } else if (engtest.toLowerCase().contains("pre sowing") ||
                      engtest.toLowerCase().contains("preparation")) {
                    _presowingCropName = cropName;
                    setState(() {
                      _isListening = false;
                    });
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CropPreparationScreen(
                          langCode: _currentLangCode,
                          cropName: _presowingCropName,
                        ),
                      ),
                    );
                    // setState(() {
                    //   _chatState = ChatState.awaitingConfirmation;
                    // });
                    // final confirmationMsg =
                    //     "Do you want to see the pre sowing preparation for $cropName? Say 'Yes' or 'No'.";
                    // final translatedMsg = await translateToNative(
                    //   confirmationMsg,
                    // );
                    // setState(() {
                    //   _isListening = false;
                    //   _messages.add(
                    //     ChatMessage(
                    //       englishText: confirmationMsg,
                    //       nativeText: translatedMsg,
                    //       isUser: false,
                    //       timestamp: DateTime.now(),
                    //     ),
                    //   );
                    // });
                    // _speakText(translatedMsg);
                    _scrollToBottom();
                  } else if (engtest.toLowerCase().contains("diagnosis") ||
                      engtest.toLowerCase().contains("diagnostic") ||
                      engtest.toLowerCase().contains("diagnose")) {
                    _diagnosis = "diagnosis";
                    setState(() {
                      _isListening = false;
                    });
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            DiagnosisScreen(widtargetLangCode: _currentLangCode),
                      ),
                    );
                    // setState(() {
                    //   _chatState = ChatState.awaitingConfirmation;
                    // });
                    // final confirmationMsg =
                    //     "Do you want to go Diagnose Plant Screen? Say 'Yes' or 'No'.";
                    // final translatedMsg = await translateToNative(
                    //   confirmationMsg,
                    // );
                    // setState(() {
                    //   _isListening = false;
                    //   _messages.add(
                    //     ChatMessage(
                    //       englishText: confirmationMsg,
                    //       nativeText: translatedMsg,
                    //       isUser: false,
                    //       timestamp: DateTime.now(),
                    //     ),
                    //   );
                    // });
                    // _speakText(translatedMsg);
                    _scrollToBottom();
                  } else if (engtest.toLowerCase().contains("market") ||
                      engtest.toLowerCase().contains("market Prices") ||
                      engtest.toLowerCase().contains("prices")) {
                    _market = "market";
                    setState(() {
                      _isListening = false;
                    });
                    Position position = await Geolocator.getCurrentPosition();
                    List<Placemark> placemarks = await placemarkFromCoordinates(
                      position.latitude,
                      position.longitude,
                    );
                    final place = placemarks.first;
                    final district = place.subAdministrativeArea ?? '';
                    final state = place.administrativeArea ?? '';

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MarketPriceScreen(
                          userDistrict: district,
                          userState: state,
                        ),
                      ),
                    );
                    // setState(() {
                    //   _chatState = ChatState.awaitingConfirmation;
                    // });
                    // final confirmationMsg =
                    //     "Do you want to go Market Prices Screen? Say 'Yes' or 'No'.";
                    // final translatedMsg = await translateToNative(
                    //   confirmationMsg,
                    // );
                    // setState(() {
                    //   _isListening = false;
                    //   _messages.add(
                    //     ChatMessage(
                    //       englishText: confirmationMsg,
                    //       nativeText: translatedMsg,
                    //       isUser: false,
                    //       timestamp: DateTime.now(),
                    //     ),
                    //   );
                    // });
                    // _speakText(translatedMsg);
                    _scrollToBottom();
                  } else if (engtest.toLowerCase().contains("weather") ||
                      engtest.toLowerCase().contains("forecast") ||
                      engtest.toLowerCase().contains("weather forecast")) {
                    _weather = "weather";
                    setState(() {
                      _isListening = false;
                    });
                    _getLocation();
                    // setState(() {
                    //   _chatState = ChatState.awaitingConfirmation;
                    // });
                    // final confirmationMsg =
                    //     "Do you want to go Weather Forecast Screen? Say 'Yes' or 'No'.";
                    // final translatedMsg = await translateToNative(
                    //   confirmationMsg,
                    // );
                    // setState(() {
                    //   _isListening = false;
                    //   _messages.add(
                    //     ChatMessage(
                    //       englishText: confirmationMsg,
                    //       nativeText: translatedMsg,
                    //       isUser: false,
                    //       timestamp: DateTime.now(),
                    //     ),
                    //   );
                    // });
                    // _speakText(translatedMsg);
                    _scrollToBottom();
                  }  else if (engtest.toLowerCase().contains("crop management") ||
                      engtest.toLowerCase().contains("crop") ||
                      engtest.toLowerCase().contains("management")) {
                    _cropmng = "cropmanage";
                    setState(() {
                      _isListening = false;
                    });
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CropManagementScreen(langCode: _currentLangCode),
                      ),
                    );
                    // setState(() {
                    //   _chatState = ChatState.awaitingConfirmation;
                    // });
                    // final confirmationMsg =
                    //     "Do you want to go Crop Management Screen? Say 'Yes' or 'No'.";
                    // final translatedMsg = await translateToNative(
                    //   confirmationMsg,
                    // );
                    // setState(() {
                    //   _isListening = false;
                    //   _messages.add(
                    //     ChatMessage(
                    //       englishText: confirmationMsg,
                    //       nativeText: translatedMsg,
                    //       isUser: false,
                    //       timestamp: DateTime.now(),
                    //     ),
                    //   );
                    // });
                    // _speakText(translatedMsg);
                    _scrollToBottom();
                  }  else if (engtest.toLowerCase().contains("post harvesting") ||
                      engtest.toLowerCase().contains("post") ||
                      engtest.toLowerCase().contains("harvesting")) {
                    _postharvest = "postharvest";
                    setState(() {
                      _isListening = false;
                    });
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            PostHarvestingScreen(langCode: _currentLangCode),
                      ),
                    );
                    // setState(() {
                    //   _chatState = ChatState.awaitingConfirmation;
                    // });
                    // final confirmationMsg =
                    //     "Do you want to go Post Harvesting Screen? Say 'Yes' or 'No'.";
                    // final translatedMsg = await translateToNative(
                    //   confirmationMsg,
                    // );
                    // setState(() {
                    //   _isListening = false;
                    //   _messages.add(
                    //     ChatMessage(
                    //       englishText: confirmationMsg,
                    //       nativeText: translatedMsg,
                    //       isUser: false,
                    //       timestamp: DateTime.now(),
                    //     ),
                    //   );
                    // });
                    // _speakText(translatedMsg);
                    _scrollToBottom();
                  } else {
                    // ---------- PREVIOUS QUERY HANDLING --------
                    _askForConfirmation(_lastRecognizedWords);
                  }
                }
              } else if (_chatState == ChatState.awaitingConfirmation) {
                setState(() {
                  _isListening = false;
                });
                print("schedule else if");
                _handleConfirmationResponse(result.recognizedWords);
              }
            });
          }
        },
        onSoundLevelChange: (level) {
          // Optional: mic level visuals
        },
      );

      // Fallback timer if user does not speak at all
      _speechActivityTimer?.cancel();
      _speechActivityTimer = Timer(const Duration(seconds: 5), () async {
        if (!userSpoke &&
            _isListening &&
            _chatState == ChatState.listeningQuery) {
          print("DEBUG: User did not speak within 5 seconds. Stopping mic.");
          _stopListening();
          setState(() {
            _chatState = ChatState.initial;
            _isListening = false;
          });

          final confirmationEnglish =
              "I didn't hear anything. Please tap the mic and try again.";
          final confirmationNative = await translateToNative(
            confirmationEnglish,
          );
          setState(() {
            _messages.add(
              ChatMessage(
                englishText: confirmationEnglish,
                nativeText: confirmationNative,
                isUser: false,
                timestamp: DateTime.now(),
              ),
            );
          });
          _speakText(confirmationNative);
        }
      });
    } else if (_speech.isListening) {
      print("Already listening, no need to start again.");
    } else if (!_speechAvailable) {
      print("Speech recognition not available.");
      _speakText("Speech recognition is not available on your device.");
    }
  }

  // ---------- LISTEN FOR CONFIRMATION ----------
  Future<void> _startListeningForConfirmation(
    String cropName,
    String cnf,
  ) async {
    setState(() {
      _isListening = false;
    });
    final engtexts = await translateNativeToEnglish(cnf);
    print(
      "_startListeningForConfirmation: $engtexts $_pendingCropName $_presowingCropName",
    );
    final engtext = engtexts.toLowerCase();
    if (engtext.contains("yes") &&
        _pendingCropName != null &&
        _pendingCropName!.isNotEmpty) {
    } else if (engtext.contains("yes") &&
        _presowingCropName != null &&
        _presowingCropName!.isNotEmpty) {
    } else if (engtext.contains("yes") &&
        _diagnosis != null &&
        _diagnosis!.isNotEmpty) {
    } else if (engtext.contains("yes") &&
        _market != null &&
        _market!.isNotEmpty) {
    } else if (engtext.contains("yes") &&
        _cropmng != null &&
        _cropmng!.isNotEmpty) {
    }else if (engtext.contains("yes") &&
        _postharvest != null &&
        _postharvest!.isNotEmpty) {
    }else if (engtext.contains("yes") &&
        _weather != null &&
        _weather!.isNotEmpty) {
    } else if (engtext.contains("no")) {
      final msg = await translateToNative(
        "Okay, please try again with a different crop name.",
      );
      setState(() {
        _chatState = ChatState.awaitingConfirmation;
        _messages.add(
          ChatMessage(
            englishText: "Cancelled",
            nativeText: msg,
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _speakText(msg);
      setState(() {
        _chatState = ChatState.initial;
      });
    } else {
      _speakText("Please say Yes or No.");
    }
  }

  Future<void> _getLocation() async {
    final savedSettings = await DatabaseHelper().getUserSettings();
    if (savedSettings != null) {
      print("📦 Loaded location from DB");
      final state = savedSettings['state'];
      final district = savedSettings['district'];
      final lang = savedSettings['language'];
      PageAPI.setLocation(district: district, state: state);
      PageAPI.logPageVisit("HomeScreen");

      try {
        final locations = await locationFromAddress("$district, $state");
        if (locations.isNotEmpty) {
          final lat = locations.first.latitude;
          final lon = locations.first.longitude;
          await _getWeather(lat, lon);
        } else {
          print("⚠️ Could not resolve location from address");
        }
      } catch (e) {
        print("❌ Geocoding failed: $e");
      }
      return;
    }
  }

 /* 
  Future<void> _getWeather(double lat, double lon) async {
  final akgl = "";

  try {
    // 1. Resolve city to locationKey
    final locUrl = Uri.parse(
      "https://dataservice.accuweather.com/locations/v1/cities/geoposition/search"
      "?apikey=$apiKey&q=$lat,$lon",
    );

    final locResp = await http.get(locUrl);
    if (locResp.statusCode != 200) {
      throw Exception("Failed to fetch locationKey");
    }
    final locData = jsonDecode(locResp.body);
    final locationKey = locData["Key"];
    final cityName = locData["LocalizedName"];
    final country = locData["Country"]["LocalizedName"];

    // 2. Fetch forecast
    final forecastUrl = Uri.parse(
      "https://dataservice.accuweather.com/forecasts/v1/daily/5day/$locationKey"
      "?apikey=$apiKey&metric=true",
    );
    final forecastResp = await http.get(forecastUrl);
    if (forecastResp.statusCode != 200) {
      throw Exception("Failed to fetch forecast");
    }

    final forecastData = jsonDecode(forecastResp.body);

    final headline = forecastData["Headline"]["Text"];
    final List forecasts = forecastData["DailyForecasts"];

    // 3. Convert into your display/speak format
    final forecastList = await Future.wait(
      forecasts.map((day) async {
        final date = day["Date"];
        final minTemp = day["Temperature"]["Minimum"]["Value"];
        final maxTemp = day["Temperature"]["Maximum"]["Value"];
        final condition = day["Day"]["IconPhrase"];
        final iconCode = day["Day"]["Icon"];

        final dayName = getDayNameInNative(date, _currentLangCode);
        final nativedayName =
            RegExp(r'\((.*?)\)').firstMatch(dayName)?.group(1) ?? '';
        final nativeCondition = await translateToNative(condition);

        final tempLabel = await translateToNative("Temperature");

        return {
          "display":
              "$dayName: $condition ($nativeCondition), "
              "$tempLabel: $minTemp°C - $maxTemp°C",
          "speak":
              "$nativedayName: $nativeCondition, "
              "$tempLabel $minTemp ರಿಂದ $maxTemp ಡಿಗ್ರಿ ಸೆಲ್ಸಿಯಸ್",
          "icon": iconCode,
        };
      }).toList(),
    );

    // 4. Navigate to your WeatherScreen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WeatherScreen(
          forecastDisplay:
              forecastList.map((e) => e['display'] as String).toList(),
          forecastSpeak:
              forecastList.map((e) => e['speak'] as String).toList(),
          forecastCodes:
              forecastList.map((e) => e['icon'] as int).toList(),
          targetLangCode: _currentLangCode,
        ),
      ),
    );
  } catch (e) {
    print("❌ Error fetching AccuWeather: $e");
  }
}
*/
  
  Future<void> _getWeather(double lat, double lon) async {
  
  try {
    final url = Uri.parse(
      'https://api.weatherapi.com/v1/forecast.json'
      '?key=1046d3b300794f6b90e122255252909'
      '&q=$lat,$lon'
      '&days=7'
      '&aqi=no&alerts=no',
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Dates from forecast
      final List dates = (data['forecast']['forecastday'] as List)
          .map((e) => e['date'])
          .toList();

      // Temperatures (max)
      final List<double> temps = (data['forecast']['forecastday'] as List)
          .map((e) => (e['day']['maxtemp_c'] as num).toDouble())
          .toList();

      // Humidity (avg)
      final List<double> humidity = (data['forecast']['forecastday'] as List)
          .map((e) => (e['day']['avghumidity'] as num).toDouble())
          .toList();

      // Wind speed (max kph)
      final List<double> wind = (data['forecast']['forecastday'] as List)
          .map((e) => (e['day']['maxwind_kph'] as num).toDouble())
          .toList();

      // Condition codes + descriptions
      final List<int> codes = (data['forecast']['forecastday'] as List)
          .map((e) => (e['day']['condition']['code'] as num).toInt())
          .toList();

      final List<String> conditions = (data['forecast']['forecastday'] as List)
          .map((e) => e['day']['condition']['text'].toString())
          .toList();

      // --- TODAY’s summary ---
      final condition = conditions[0];
      final nativeCondition = await translateToNative(condition);

      // --- FULL Forecast ---
      final forecastList = await Future.wait(
        List.generate(dates.length, (i) async {
          final dayName = getDayNameInNative(dates[i], _currentLangCode);
          final nativedayName =
              RegExp(r'\((.*?)\)').firstMatch(dayName)?.group(1) ?? '';

          final nativeDesc = await translateToNative(conditions[i]);
          final englishDesc = conditions[i];

          final tempVal = temps[i].toStringAsFixed(1);
          final humVal = humidity[i].toStringAsFixed(0);
          final windVal = wind[i].toStringAsFixed(0);

          final temp = convertToNativeDigits(tempVal, _currentLangCode);
          final hum = convertToNativeDigits(humVal, _currentLangCode);
          final winds = convertToNativeDigits(windVal, _currentLangCode);

          final tempLabel = await translateToNative('Temperature');
          final humLabel = await translateToNative('Humidity');
          final windLabel = await translateToNative('Wind');

          return {
            "display":
                "$dayName: $englishDesc ($nativeDesc), "
                "$tempLabel: $tempVal°C, "
                "💧 Humidity ($humLabel): $humVal%, "
                "🌬️ Wind ($windLabel): $windVal km/h",
            "speak":
                "$nativedayName: $nativeDesc, "
                "$tempLabel: $temp ಡಿಗ್ರಿ ಸೆಲ್ಸಿಯಸ್, "
                "$humLabel: $hum ಶೇಕಡಾ, "
                "$windLabel: $winds ಕಿ.ಮೀ/ಗಂ",
          };
        }),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WeatherScreen(
            forecastDisplay:
                forecastList.map((e) => e['display'] as String).toList(),
            forecastSpeak:
                forecastList.map((e) => e['speak'] as String).toList(),
            forecastCodes: codes,
            targetLangCode: _currentLangCode,
          ),
        ),
      );
    } else {
      print("❌ Error: ${response.statusCode}");
    }
  } catch (e) {
    print("❌ Exception fetching weather: $e");
  }
  }

  String getDayNameInNative(String date, String langCode) {
    final dateTime = DateTime.parse(date);
    final weekdayIndex = dateTime.weekday - 1; // 0-based index

    const englishWeekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final nativeWeekdays =
        weekdayTranslations[langCode] ?? weekdayTranslations['en']!;
    final native = nativeWeekdays[weekdayIndex];
    final english = englishWeekdays[weekdayIndex];

    return '$english ($native)';
  }

  Map<String, List<String>> weekdayTranslations = {
    'en': [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ],
    'kn': [
      'ಸೋಮವಾರ',
      'ಮಂಗಳವಾರ',
      'ಬುಧವಾರ',
      'ಗುರುವಾರ',
      'ಶುಕ್ರವಾರ',
      'ಶನಿವಾರ',
      'ಭಾನುವಾರ',
    ],
    'hi': [
      'सोमवार',
      'मंगलवार',
      'बुधवार',
      'गुरुवार',
      'शुक्रवार',
      'शनिवार',
      'रविवार',
    ],
    'ta': [
      'திங்கள்',
      'செவ்வாய்',
      'புதன்',
      'வியாழன்',
      'வெள்ளி',
      'சனி',
      'ஞாயிறு',
    ],
    'te': [
      'సోమవారం',
      'మంగళవారం',
      'బుధవారం',
      'గురువారం',
      'శుక్రవారం',
      'శనివారం',
      'ఆదివారం',
    ],
    'ml': ['തിങ്കള്‍', 'ചൊവ്വ', 'ബുധന്‍', 'വ്യാഴം', 'വെള്ളി', 'ശനി', 'ഞായര്‍'],
    'bn': [
      'সোমবার',
      'মঙ্গলবার',
      'বুধবার',
      'বৃহস্পতিবার',
      'শুক্রবার',
      'শনিবার',
      'রবিবার',
    ],
  };

  String convertToNativeDigits(String number, String langCode) {
    const digitMaps = {
      'kn': ['೦', '೧', '೨', '೩', '೪', '೫', '೬', '೭', '೮', '೯'],
      'hi': ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'],
      'ta': ['௦', '௧', '௨', '௩', '௪', '௫', '௬', '௭', '௮', '௯'],
      'te': ['౦', '౧', '౨', '౩', '౪', '౫', '౬', '౭', '౮', '౯'],
      // Add more as needed
    };

    final digits =
        digitMaps[langCode] ??
        ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    return number.split('').map((c) {
      final i = int.tryParse(c);
      return (i != null) ? digits[i] : c;
    }).join();
  }

  String getWeatherDescFromCode(int code) {
    const mapping = {
      0: 'Clear sky',
      1: 'Mainly clear',
      2: 'Partly cloudy',
      3: 'Overcast',
      45: 'Fog',
      48: 'Depositing rime fog',
      51: 'Light drizzle',
      53: 'Moderate drizzle',
      55: 'Dense drizzle',
      61: 'Slight rain',
      63: 'Moderate rain',
      65: 'Heavy rain',
      71: 'Slight snow',
      73: 'Moderate snow',
      75: 'Heavy snow',
      80: 'Rain showers',
      81: 'Heavy rain showers',
      82: 'Violent rain showers',
      95: 'Thunderstorm',
      96: 'Thunderstorm with slight hail',
      99: 'Thunderstorm with heavy hail',
    };
    return mapping[code] ?? 'Unknown';
  }

  String getDayName(String date) {
    final dateTime = DateTime.parse(date);
    final weekday = dateTime.weekday;
    const weekdays = [
      '', // index 0 placeholder
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[weekday];
  }

  Future<List<Map<String, dynamic>>> fetchUserCropSchedule(
    String userId,
    String cropName,
  ) async {
    try {
      final url = Uri.parse(
        "http://172.20.10.5:3000/api/cropcalendarbyuser?userId=$userId&cropName=$cropName",
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        print("Failed to fetch crop schedule: ${response.body}");
        return [];
      }
    } catch (e) {
      print("Error fetching crop schedule: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchPreCrop(
    String userId,
    String cropName,
  ) async {
    try {
      final url = Uri.parse(
        "http://172.20.10.5:3000/api/preparation/$cropName",
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final steps = data['steps'] as List<dynamic>;
        // final List<dynamic> data = json.decode(response.body);
        return steps.cast<Map<String, dynamic>>();
      } else {
        print("Failed to fetch crop pre sowing: ${response.body}");
        return [];
      }
    } catch (e) {
      print("Error fetching crop  pre sowing: $e");
      return [];
    }
  }

  // ---------- HANDLE CONFIRMED CROP ----------
  void _handleConfirmedCrop(String cropName) async {
    setState(() {
      _chatState = ChatState.initial;
      _isListening = false;
    });
    final id = await getOrCreateDeviceId();
    final events = await fetchUserCropSchedule(id, cropName);

    if (events.isEmpty) {
      final msg = await translateToNative(
        "No schedule found for $cropName for you.",
      );
      setState(() {
        _messages.add(
          ChatMessage(
            englishText: "No schedule found for $cropName for you.",
            nativeText: msg,
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _speakText(msg);
      return;
    }
    // Navigate to CalendarScreen and pass the events
  }

  void _handleConfirmedPreCrop(String cropName) async {
    setState(() {
      _chatState = ChatState.initial;
      _isListening = false;
    });
    final id = await getOrCreateDeviceId();
    final events = await fetchPreCrop(id, cropName);
    print("Pre Api; $events $cropName");
    if (events.isEmpty) {
      final msg = await translateToNative(
        "No Pre sowing Preparations found for $cropName for you.",
      );
      setState(() {
        _messages.add(
          ChatMessage(
            englishText:
                "No Pre sowing Preparations found for $cropName for you.",
            nativeText: msg,
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _speakText(msg);
      return;
    }
    // Navigate to CalendarScreen and pass the events
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

  final List<String> supportedCrops = ["tomato"];

  String? extractCropName(String query) {
    for (var crop in supportedCrops) {
      if (query.contains(crop.toLowerCase())) {
        return crop;
      }
    }
    return null;
  }

  void _resetSilenceTimer() {
    _speechActivityTimer?.cancel();
    _speechActivityTimer = Timer(const Duration(seconds: 5), () {
      if (_isListening && _chatState == ChatState.listeningQuery) {
        print("⏱️ 5 seconds of silence. Stopping mic.");
        _stopListening();
      }
    });
  }

  void _stopListening() async {
    if (_speech.isListening) {
      print("DEBUG: _stopListening: Calling _speech.stop().");
      await _speech.stop(); // Stop the speech recognizer
    }
    _speechActivityTimer?.cancel(); // Cancel any active timer
  }

  Future<List<Crop>> _fetchAllCrops() async {
    try {
      final response = await http.get(Uri.parse('$_apiBaseUrl/crops'));
      if (response.statusCode == 200) {
        List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => Crop.fromJson(json)).toList();
      } else {
        print('Failed to load crops: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching crops: $e');
      return [];
    }
  }

  // --- Query Handling Logic ---
  // A simplified example of how to handle user queries.
  // In a real application, this would involve more sophisticated NLP.
  Future<String> _handleQuery(String englishQuery) async {
    print('English query:  ${englishQuery} ');
    final lowerQuery = englishQuery.toLowerCase();
    final cachedResponse = await DatabaseHelper().getQueryResponse(
      englishQuery,
    );
    if (cachedResponse != null) {
      print('✅ Found cached response in query_response table.');
      return cachedResponse;
    } else if (englishQuery.toLowerCase().contains('temperature') &&
        englishQuery.toLowerCase().contains('rice')) {
      return "Rice grows best at temperatures between 20°C and 35°C.";
    } else if (((lowerQuery.contains('water') ||
                lowerQuery.contains('irrigation')) &&
            lowerQuery.contains('rice')) ||
        lowerQuery.contains('does rice need')) {
      return "Rice requires continuous flooding with 5 to 10 cm of water throughout most of its growth.";
    } else if ((lowerQuery.contains('planting') ||
            lowerQuery.contains('season') ||
            lowerQuery.contains('sowing')) &&
        lowerQuery.contains('rice')) {
      return "In India, rice is usually planted during the Kharif season, which starts in June or July.";
    } else if ((lowerQuery.contains('fertilizer') ||
            lowerQuery.contains('manure') ||
            lowerQuery.contains('nutrients')) &&
        lowerQuery.contains('rice')) {
      return "Rice cultivation benefits from fertilizers rich in nitrogen, phosphorus, and potassium.";
    } else if (((lowerQuery.contains('variety') ||
                lowerQuery.contains('varieties') ||
                lowerQuery.contains('type')) &&
            lowerQuery.contains('rice')) ||
        lowerQuery.contains('variety of rise')) {
      return "Popular varieties of rice in India include Basmati, Sona Masuri, IR64, Ponni, and Gobindobhog.";
    } else if ((lowerQuery.contains('basmati') &&
            lowerQuery.contains('rice')) ||
        lowerQuery.contains('basuma')) {
      return "Basmati rice is a long-grain aromatic rice grown mainly in India and Pakistan, known for its distinct fragrance and fluffy texture.";
    } else if (((lowerQuery.contains('how long') ||
                lowerQuery.contains('duration') ||
                lowerQuery.contains('time')) &&
            lowerQuery.contains('rice')) ||
        lowerQuery.contains('how long does rise to grow')) {
      return "Rice generally takes about 3 to 6 months to grow, depending on the variety and environmental conditions.";
    } else if (((lowerQuery.contains('pest') ||
                lowerQuery.contains('insect') ||
                lowerQuery.contains('bug')) &&
            lowerQuery.contains('rice')) ||
        lowerQuery.contains('effect')) {
      return "Common pests in rice cultivation include stem borers, leaf folders, brown planthoppers, and gall midges.";
    } else if ((lowerQuery.contains('disease') ||
            lowerQuery.contains('infection') ||
            lowerQuery.contains('virus')) &&
        lowerQuery.contains('rice')) {
      return "Major rice diseases include blast, sheath blight, bacterial leaf blight, and tungro virus.";
    } else if ((((lowerQuery.contains('yield') ||
                    lowerQuery.contains('production') ||
                    lowerQuery.contains('per hectare')) &&
                lowerQuery.contains('rice')) ||
            lowerQuery.contains("per")) ||
        lowerQuery.contains('what is the effect')) {
      return "In India, the average yield of rice is around 2.7 to 3.5 tons per hectare, depending on the region and variety.";
    } else {
      return "I don't have information on that. Searching in Google.";
    }
    if (englishQuery.toLowerCase().contains('details of') ||
        englishQuery.toLowerCase().contains('info about') ||
        englishQuery.toLowerCase().contains('tell me about') ||
        englishQuery.toLowerCase().contains('tell about')) {
      final cropNameMatch = RegExp(
        r'(details of|info about|tell me about|tell about)\s+(\w+)',
      ).firstMatch(englishQuery.toLowerCase());
      if (cropNameMatch != null && cropNameMatch.groupCount >= 2) {
        final requestedCropName = cropNameMatch.group(2)!;
        print('User requested details for crop: $requestedCropName');
        return _getCropDetailsResponse(requestedCropName);
      }
    }

    // Fallback to generic responses if no specific intent is matched
    if (englishQuery.toLowerCase().contains('hello') ||
        englishQuery.toLowerCase().contains('hi')) {
      return "Hello there! How can I assist you?";
    } else if (englishQuery.toLowerCase().contains('weather')) {
      return "I can't provide real-time weather here, but your main screen has weather info!";
    } else if (englishQuery.toLowerCase().contains('crop')) {
      return "For general crop information, please use the 'Crop Info' button on the main screen. If you're looking for specific crop details, try asking 'details of [crop name]'.";
    } else if (englishQuery.toLowerCase().contains('holiday')) {
      return "You can check holidays using the 'Show Holidays' button on the main screen.";
    } else if (englishQuery.toLowerCase().contains('market price')) {
      return "Market prices can be viewed via the 'Market Prices' button on the main screen.";
    } else {
      return "You said: '$englishQuery'. I'm a simple chatbot for now. Try asking about weather, crops, or just say hello!";
    }
  }

  Future<String> _getCropDetailsResponse(String requestedCropName) async {
    final allCrops = await _fetchAllCrops();
    final foundCrop = allCrops.firstWhere(
      (crop) => crop.cropName.toLowerCase() == requestedCropName.toLowerCase(),
      orElse: () => Crop(
        cropID: -1,
        cropName: 'Not Found',
        variety: '',
        plantType: '',
      ), // Placeholder
    );

    if (foundCrop.cropID != -1) {
      return "Here are the details for ${foundCrop.cropName}:\n"
          "Variety: ${foundCrop.variety}\n"
          "Plant Type: ${foundCrop.plantType}\n"
          "Region: ${foundCrop.region ?? 'N/A'}\n";
    } else {
      return "I couldn't find any details for '$requestedCropName'. Please try another crop name.";
    }
  }

  void _askForConfirmation(String nativeQuery) async {
    _lastRecognizedWords =
        nativeQuery; // ✅ Ensure this always holds the last query (if not already set)
    _query = nativeQuery;
    print('English in _askForConfirmation: ${_query}');
    setState(() {
      _chatState = ChatState.awaitingConfirmation; // Set state for confirmation
    });
    _isListening = false;
    _chatState = ChatState.awaitingConfirmation;
    final confirmationEnglish =
        "Do you want to search for this information? Say 'Yes' or 'No'.";
    final confirmationNative = await translateToNative(confirmationEnglish);

    // Add confirmation message to chat history (this is the assistant's message)
    setState(() {
      _messages.add(
        ChatMessage(
          englishText: confirmationEnglish,
          nativeText: confirmationNative,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    });
    await _speakText(confirmationNative);
    _scrollToBottom();
  }

  void _handleConfirmationResponse(String recognizedWords) async {
    print('English in _handleConfirmationResponse: ${_query}');
    final recognized = recognizedWords.toLowerCase();
    print(
      "DEBUG: Confirmation recognized: $recognized $_presowingCropName and $_pendingCropName",
    );
    if (recognized.contains('yes') ||
        recognized.contains('yeah') ||
        recognized.contains('sure') ||
        recognized.contains('ಹೌದು') ||
        recognized.contains('ಎಸ್')) {
      print("DEBUG: User said YES.");
      _stopListening(); // Stop confirmation listening
      _processConfirmedQuery();
      _textController.clear(); // Clear text box immediately after processing
    }
    // Check for "No" variations including Kannada "ಇಲ್ಲ"
    else if (recognized.contains('no') ||
        recognized.contains('nope') ||
        recognized.contains('nah') ||
        recognized.contains('ಇಲ್ಲ') ||
        recognized.contains('ನೋ')) {
      print("DEBUG: User said NO.");
      _stopListening(); // Stop confirmation listening
      _cancelQuery();
      _textController.clear(); // Clear text box immediately after processing
    } else {
      // If something else is said, re-prompt for confirmation
      final confirmationEnglish = "Please say 'Yes' or 'No'.";
      final confirmationNative = await translateToNative(confirmationEnglish);
      _speakText(confirmationNative);
      // Reset the timer as user spoke, even if not 'Yes'/'No'
      _speechActivityTimer?.cancel();
      _speechActivityTimer = Timer(const Duration(seconds: 15), () {
        if (_isListening && _chatState == ChatState.awaitingConfirmation) {
          print(
            "DEBUG: No valid confirmation received within 15 seconds, re-asking.",
          );
          _askForConfirmation(_lastRecognizedWords); // Re-ask for confirmation
        }
      });
    }
  }

  void _processConfirmedQuery() async {
    _speechActivityTimer?.cancel(); // Cancel any active timer
    await _speech.stop(); // Ensure mic is off
    setState(() {
      _isListening = false; // Ensure mic button is off
      _isSending = true; // Show loading indicator
      _isMicEnabled = false;
      _chatState = ChatState.queryConfirmed; // Update state
    });
    print(
      "DEBUG: _processConfirmedQuery: _isListening set to FALSE. Mic button should be GREY.",
    );

    _scrollToBottom();
    _speakText(
      await translateToNative("Searching for the information..."),
    ); // Announce search

    // Translate the confirmed query to English and handle it
    final englishQueryForProcessing = await translateNativeToEnglish(_query);
    final englishResponse = await _handleQuery(englishQueryForProcessing);
    final nativeResponse = await translateToNative(englishResponse);

    // Add response to chat history

    setState(() {
      _messages.add(
        ChatMessage(
          englishText: englishResponse,
          nativeText: nativeResponse,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
      _isSending = false; // Hide loading indicator
      _chatState = ChatState.responseDisplayed; // Update state
      _isMicEnabled = true;
    });
    _speakText(nativeResponse); // Speak the response
    _scrollToBottom();
    if (isFallbackNeeded(_messages)) {
      final serpResults = await fetchSerpResults(_query);

      if (serpResults.isNotEmpty) {
        for (final result in serpResults) {
          final resp =
              "${result['title'] ?? ''}\n${result['snippet'] ?? ''}\n${result['link'] ?? ''}";
          final nativeresp = await translateToNative(
            "${result['title'] ?? ''}\n${result['snippet'] ?? ''}",
          );

          setState(() {
            _messages.add(
              ChatMessage(
                englishText: resp,
                nativeText: '',
                isUser: false,
                timestamp: DateTime.now(),
              ),
            );
          });
          if (serpResults.indexOf(result) == serpResults.length - 1) {
            _speakText(nativeresp);
          } // Optional: You can choose to speak only the first one if it's too much
        }
        _scrollToBottom();
      } else {
        final respfl = "Sorry, I couldn’t find anything online either.";
        final nativerespfl = await translateToNative(respfl);
        setState(() {
          _messages.add(
            ChatMessage(
              englishText: respfl,
              nativeText: nativerespfl,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
      }
    }

    //_addInitialWelcomeMessage(); // Prompt for next query
  }

  void _cancelQuery() async {
    _speechActivityTimer?.cancel(); // Cancel any active timer
    await _speech.stop(); // Ensure mic is off
    setState(() {
      _isListening = false; // Ensure mic button is off
      _textController.clear();
      _lastRecognizedWords = ''; // Clear the stored query
      _chatState = ChatState.initial; // Reset to initial state
    });
    print(
      "DEBUG: _cancelQuery: _isListening set to FALSE. Mic button should be GREY.",
    );

    // Display and speak the "query ended" message
    final cancelEnglish = "Your query has been cancelled.";
    final cancelNative = await translateToNative(cancelEnglish);
    setState(() {
      _messages.add(
        ChatMessage(
          englishText: cancelEnglish,
          nativeText: cancelNative,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    });
    _speakText(cancelNative);
    _scrollToBottom();
    //_addInitialWelcomeMessage(); // Prompt for next query
  }

  // Helper to scroll the chat to the latest message
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Helper to speak text using TTS
  Future<void> _speakText(String text) async {
    await flutterTts.setLanguage(_currentLangCode);
    await flutterTts.speak(text);
  }

  Future<List<Map<String, dynamic>>> fetchSerpResults(String query) async {
    final apiKey =
        'cddad9eaa32fa99528259fe4b2c52264e7e20bbb0a3fe87dc349e6255d2109b8'; // Replace with your key
    final url = Uri.parse(
      'https://serpapi.com/search.json?q=$query&hl=en&gl=in&api_key=$apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // Extract results (top 5 organic)
      final results = data['organic_results'] as List;
      return results.take(5).map((result) {
        return {
          'title': result['title'],
          'snippet': result['snippet'],
          'link': result['link'],
        };
      }).toList();
    } else {
      throw Exception('Failed to load results');
    }
  }

  bool isFallbackNeeded(List<ChatMessage> messages) {
    if (messages.isEmpty) return false;

    final last = messages.last;
    final knownFallbacks = [
      "I don't know",
      "I can't provide",
      "For general crop information",
      "You can check holidays",
      "You said:",
      "Market prices",
      "I don't have information on that. Searching in Google.",
      "Sorry, I don't have that information",
      "I couldn’t find anything",
    ];

    return !last.isUser &&
        knownFallbacks.any(
          (fallback) =>
              last.englishText.toLowerCase().contains(fallback.toLowerCase()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(
          color: Colors.white, // back button color
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 📝 Title (with translation)
            Expanded(
              child: FutureBuilder<String>(
                future: translateToNative("Chat with Assistant"),
                builder: (context, snapshot) {
                  return Text(
                    "Chat with Assistant\n(${snapshot.data ?? ''})",
                    style: const TextStyle(
                      color: Colors.white, // white text color
                      fontWeight: FontWeight.w700, // bold
                      fontSize: 20, // adjust as needed
                    ),
                  );
                },
              ),
            ),

            const SizedBox(width: 12), // optional spacing
            // 🌱 Logo Image
            Image.asset(
              "assets/logo.png", // same logo as other screens
              height: 60, // adjust height to fit AppBar
              fit: BoxFit.contain,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          // Show loading indicator when sending query
          if (_isSending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  // Builds a single chat message bubble
  Widget _buildMessageBubble(ChatMessage message) {
    final alignment = message.isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final color = message.isUser ? Colors.blue[100] : Colors.grey[200];
    final textColor = Colors.black87; // Consistent text color
    final borderRadius = message.isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(15),
            bottomLeft: Radius.circular(15),
            bottomRight: Radius.circular(15),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(15),
            bottomLeft: Radius.circular(15),
            bottomRight: Radius.circular(15),
          );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Row(
            mainAxisAlignment: message.isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Speaker icon for assistant messages
              if (!message.isUser)
                Container(
                  margin: const EdgeInsets.only(
                    right: 6.0,
                  ), // spacing between icon & bubble
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.volume_up, size: 20),
                    color: Colors.white,
                    onPressed: () => _speakText(message.nativeText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    splashRadius: 20,
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 10.0,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: borderRadius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // English text
                    Text(
                      message.englishText,
                      style: TextStyle(color: textColor, fontSize: 16.0),
                    ),
                    // Native text if different from English
                    if (message.englishText != message.nativeText)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          message.nativeText,
                          style: TextStyle(
                            color: textColor.withOpacity(0.7),
                            fontSize: 14.0,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Timestamp for the message
          Padding(
            padding: const EdgeInsets.only(top: 4.0, right: 8.0, left: 8.0),
            child: Text(
              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(color: Colors.grey[600], fontSize: 10.0),
            ),
          ),
        ],
      ),
    );
  }

  // Builds the input area with microphone and confirmation buttons
  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Speak ...',
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 14),
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      readOnly:
                          true, // Make text box non-editable, only displays recognized speech
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          // Mic button for Start/Stop
          FloatingActionButton(
            heroTag: 'mic_control_qr', // Unique tag for Hero animations
            mini: true, // Smaller button
            backgroundColor: _isListening
                ? Colors.red
                : Colors.green, // Red when listening, grey when not
            onPressed: _isMicEnabled
                ? () {
                    if (_isListening) {
                      _stopListening();
                      setState(() => _isListening = false);
                    } else {
                      _startListening();
                    }
                  }
                : null, // Disable button when mic is disabled
            child: Icon(
              _isListening
                  ? Icons.mic
                  : Icons.mic_off, // Change icon based on listening state
              size: 28,
            ),
          ),
          // Removed Conditional buttons for confirmation (Yes/No)
        ],
      ),
    );
  }
}
