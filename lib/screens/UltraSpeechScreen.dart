// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
// import 'package:manual_speech_to_text/manual_speech_to_text.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:flutter_tts/flutter_tts.dart';
// import 'package:google_mlkit_translation/google_mlkit_translation.dart';
// import 'dart:async'; // Import for Timer

//     // --- API Configuration ---
//     // IMPORTANT: For Android Emulator, use '10.0.2.2' to access 'localhost' on your host machine.
//     // For physical devices, use your computer's actual IP address (e.g., '192.168.1.X').
//     const String _apiBaseUrl = 'http://172.20.10.5:3000/api';

//     // Enum for managing chat flow states
//     enum ChatState {
//     initial, // Ready for a new query
//     listeningQuery, // User is currently speaking their initial query
//     awaitingConfirmation, // Confirmation message displayed, listening for Yes/No
//     queryConfirmed, // Query confirmed, processing
//     responseDisplayed, // Response displayed
//     exiting, // System is ending a flow
//     }

//     // Data Model for a Chat Message
//     class ChatMessage {
//     final String englishText;
//     final String nativeText;
//     final bool isUser;
//     final DateTime timestamp;

//     ChatMessage({
//         required this.englishText,
//         required this.nativeText,
//         required this.isUser,
//         required this.timestamp,
//     });
//     }

//     // Data Model for Crop (matches your SQL table structure)
//     class Crop {
//     final int cropID;
//     final String cropName;
//     final String variety;
//     final String plantType;
//     final String? imageUrl;
//     final String? region;

//     Crop({
//         required this.cropID,
//         required this.cropName,
//         required this.variety,
//         required this.plantType,
//         this.imageUrl,
//         this.region,
//     });

//     factory Crop.fromJson(Map<String, dynamic> json) {
//         return Crop(
//         cropID: json['CropID'],
//         cropName: json['CropName'],
//         variety: json['Variety'],
//         plantType: json['PlantType'],
//         imageUrl: json['ImageURL'],
//         region: json['Region'],
//         );
//     }
//     }

//     class QueryResponseScreen extends StatefulWidget {
//     final String initialLangCode;

//     const QueryResponseScreen({Key? key, required this.initialLangCode}) : super(key: key);

//     @override
//     _QueryResponseScreenState createState() => _QueryResponseScreenState();
//     }

//     class _QueryResponseScreenState extends State<QueryResponseScreen> with WidgetsBindingObserver {
//     final TextEditingController _textController = TextEditingController();
//     final List<ChatMessage> _messages = [];
//     final ScrollController _scrollController = ScrollController();

//     late ManualSpeechToText _speech;
//     bool _isListening = false;
//     bool _speechAvailable = false;
//     late FlutterTts flutterTts;

//     bool _isSending = false;
//     ChatState _chatState = ChatState.initial;

//     // This timer now handles both 10s query silence and 15s confirmation silence
//     Timer? _speechActivityTimer;
//     String _lastRecognizedWords = ''; // Stores the query for confirmation

//     late String _currentLangCode;
//     bool _isMicEnabled = true;

//     @override
//     void initState() {
//         super.initState();
//         WidgetsBinding.instance.addObserver(this); // Add observer for lifecycle events
//         _currentLangCode = widget.initialLangCode;

//         flutterTts = FlutterTts();
//         _initTts();

//         _speech = stt.SpeechToText();
//         _initSpeechRecognizer();

//         _addInitialWelcomeMessage();
//     }

//     @override
//     void dispose() {
//         WidgetsBinding.instance.removeObserver(this); // Remove observer
//         _textController.dispose();
//         _scrollController.dispose();
//         _speech.stop(); // Ensure speech recognizer is stopped
//         //_speech.cancel(); // Cancel any pending operations
//         flutterTts.stop(); // Stop any ongoing speech
//         _speechActivityTimer?.cancel(); // Cancel any active timers
//         super.dispose();
//     }

//     @override
//     void didChangeAppLifecycleState(AppLifecycleState state) {
//         print("AppLifecycleState: $state");
//         // When the app goes to the background or is detached, stop speech recognition
//         if (state == AppLifecycleState.paused) {
//         if (_isListening) {
//             _speech.stop();
//             setState(() {
//             _isListening = false;
//             });
//             print("Mic paused due to app lifecycle state (paused).");
//         }
//         } else if (state == AppLifecycleState.detached) {
//         _speech.stop();
//         //_speech.cancel();
//         flutterTts.stop();
//         _speechActivityTimer?.cancel();
//         print("Mic stopped and resources disposed due to app being detached.");
//         }
//     }

//     Future<void> _initTts() async {
//         // Set TTS language, rate, and pitch for natural speech
//         await flutterTts.setLanguage(_currentLangCode);
//         await flutterTts.setSpeechRate(0.5);
//         await flutterTts.setPitch(1.0);
//     }

//     Future<void> _initSpeechRecognizer() async {
//         // Request microphone permission
//         final micStatus = await Permission.microphone.request();
//         if (!micStatus.isGranted) {
//         print("Microphone permission not granted for QueryResponseScreen.");
//         return; // Cannot proceed without permission
//         }

//         // Initialize speech recognition
//         _speechAvailable = await _speech.initialize(
//         onStatus: (status) {
//             print("Speech status (QR): $status (isListening: $_isListening, chatState: $_chatState)");
//             if (status == 'notListening' && _isListening) {
//             // The speech recognizer has stopped, and our app thought it was listening
//             print("DEBUG: onStatus: notListening received and _isListening was true. Setting _isListening to FALSE.");
//             setState(() {
//                 _isListening = false; // Update UI: mic button turns grey
//             });
//             _speechActivityTimer?.cancel(); // Cancel any active timer

//             if (_chatState == ChatState.listeningQuery) {
//                 if (_textController.text.isNotEmpty) {
//                     _lastRecognizedWords = _textController.text; // Store the final recognized query

//                     // Add the user message BEFORE confirmation prompt
//                     setState(() {
//                         _messages.add(ChatMessage(
//                         englishText: _lastRecognizedWords, // Use the recognized words as English text
//                         nativeText: _lastRecognizedWords, // Use the recognized words as native text
//                         isUser: true,
//                         timestamp: DateTime.now(),
//                         ));
//                     });
//                     _scrollToBottom();
//                     _textController.clear(); // Clear the text box immediately after adding user message

//                     // Ask for confirmation AFTER showing user message and clearing text box
//                     _askForConfirmation(_lastRecognizedWords);
//                 } else {
//                 // Mic stopped, but no voice was recognized for the initial query
//                 _speakText("Sorry, I didn't catch that. Please try again.");
//                 setState(() {
//                     _chatState = ChatState.initial; // Reset to initial state
//                 });
//                 _textController.clear();
//                 _addInitialWelcomeMessage(); // Re-add the welcome message
//                 }
//             } else if (_chatState == ChatState.awaitingConfirmation) {
//                 // Mic stopped during confirmation listening (e.g., due to manual tap or external interruption)
//                 // If the _speechActivityTimer for confirmation is NOT active, it means it wasn't a timeout,
//                 // so we should re-prompt immediately. If it IS active, the timer will handle the re-prompt.
//                 if (_speechActivityTimer == null || !_speechActivityTimer!.isActive) {
//                     print("DEBUG: Mic stopped during confirmation (not by timeout), re-prompting.");
//                     _speakText("Please give the confirmation. Say 'Yes' or 'No'.");
//                     _startListeningForConfirmation(); // Restart listening for confirmation
//                 }
//             }
//             } else if (status == 'listening') {
//             print("DEBUG: onStatus: listening received. Setting _isListening to TRUE.");
//             setState(() {
//                 _isListening = true; // Update UI: mic button turns red
//             });
//             print("Successfully listening (QR).");
//             }
//         },
//         onError: (error) {
//             // Handle any errors from speech recognition
//             print("Speech error (QR): $error");
//             setState(() {
//             _isListening = false; // Turn off mic UI
//             _chatState = ChatState.initial; // Reset state on error
//             });
//             _speechActivityTimer?.cancel(); // Cancel any active timers
//             _speakText("An error occurred with speech recognition. Please try again.");
//             _textController.clear();
//             _addInitialWelcomeMessage(); // Re-add the welcome message
//         },
//         );
//         print("Speech recognizer initialized (QR): $_speechAvailable");
//     }

//     Future<void> _addInitialWelcomeMessage() async {
//         final welcomeEnglish = "Hello! How can I help you today?";
//         final welcomeNative = await translateToNative(welcomeEnglish);
//         setState(() {
//         _messages.add(ChatMessage(
//             englishText: welcomeEnglish,
//             nativeText: welcomeNative,
//             isUser: false,
//             timestamp: DateTime.now(),
//         ));
//         _chatState = ChatState.initial; // Ensure state is initial
//         });
//         _speakText(welcomeNative); // Speak the welcome message
//         _scrollToBottom(); // Scroll to the latest message
//     }

//     // Helper to get MLKit TranslateLanguage from custom language codes
//     TranslateLanguage _getMLKitLanguage(String langCode) {
//         switch (langCode) {
//         case 'hi': return TranslateLanguage.hindi;
//         case 'bn': return TranslateLanguage.bengali;
//         case 'gu': return TranslateLanguage.gujarati;
//         case 'kn': return TranslateLanguage.kannada;
//         case 'mr': return TranslateLanguage.marathi;
//         case 'ta': return TranslateLanguage.tamil;
//         case 'te': return TranslateLanguage.telugu;
//         case 'ur': return TranslateLanguage.urdu;
//         default: return TranslateLanguage.english; // Default to English
//         }
//     }

//     // Translates English text to the user's selected native language
//     Future<String> translateToNative(String text) async {
//         try {
//         final translator = OnDeviceTranslator(
//             sourceLanguage: TranslateLanguage.english,
//             targetLanguage: _getMLKitLanguage(_currentLangCode),
//         );
//         final translated = await translator.translateText(text);
//         await translator.close(); // Close translator to release resources
//         return translated;
//         } catch (e) {
//         print("❌ Translation to native failed: $e");
//         return text; // Return original text on failure
//         }
//     }

//     // Translates native text back to English for query processing
//     Future<String> translateNativeToEnglish(String nativeText) async {
//         try {
//         final modelManager = OnDeviceTranslatorModelManager();
//         // Ensure the English model is downloaded for translation to English
//         final isEnglishModelDownloaded = await modelManager.isModelDownloaded('en');
//         if (!isEnglishModelDownloaded) {
//             print("Downloading English translation model...");
//             await modelManager.downloadModel('en', isWifiRequired: false);
//         }

//         final translator = OnDeviceTranslator(
//             sourceLanguage: _getMLKitLanguage(_currentLangCode),
//             targetLanguage: TranslateLanguage.english,
//         );
//         final translatedText = await translator.translateText(nativeText);
//         await translator.close();
//         return translatedText;
//         } catch (e) {
//         print("❌ Native ➜ English translation failed: $e");
//         return nativeText; // Return original text on failure
//         }
//     }

//     // Helper to get SpeechToText locale ID from custom language codes
//     String getSpeechLocale(String langCode) {
//         switch (langCode) {
//         case 'hi': return 'hi-IN';
//         case 'kn': return 'kn-IN';
//         case 'ta': return 'ta-IN';
//         case 'te': return 'te-IN';
//         case 'ml': return 'ml-IN'; // Malayalam added for completeness if supported
//         case 'mr': return 'mr-IN';
//         case 'bn': return 'bn-IN';
//         case 'gu': return 'gu-IN';
//         case 'ur': return 'ur-IN';
//         default: return 'en-IN'; // Default to Indian English
//         }
//     }
//     bool _hasUserSpoken = false;
//     void _startListening() async {
//         // Check and request microphone permission if not granted
//         final micStatus = await Permission.microphone.status;
//         if (!micStatus.isGranted) {
//             final result = await Permission.microphone.request();
//             if (!result.isGranted) {
//                 print("Microphone permission not granted.");
//                 _speakText("Microphone permission is required to use voice input.");
//                 return;
//             }
//         }

//         if (_speechAvailable && !_speech.isListening) {
//             setState(() {
//                 _isListening = true; // Mic on UI
//                 _textController.clear(); // Clear previous input to show new live transcription
//                 _lastRecognizedWords = ''; // Clear last query
//                 _chatState = ChatState.listeningQuery; // Set state to listening for initial query
//             });
//             print("🎤 Mic started. Listening...");
//             bool userSpoke = false; 

//             _speech.listen(
//                 localeId: getSpeechLocale(_currentLangCode),
//                 listenMode: stt.ListenMode.dictation, // Optimized for continuous dictation
//                 onResult: (result) async {
//                     if (result.recognizedWords.trim().isNotEmpty) {
//                         userSpoke = true;
//                         setState(() {
//                         _textController.text = result.recognizedWords; // Display live recognized text in input box
//                         });
                        
                    
//                         // Reset the 10-second activity timer on new speech
//                         _speechActivityTimer?.cancel();
//                         _speechActivityTimer = Timer(const Duration(seconds: 5), () {
//                         if (_isListening && _chatState == ChatState.listeningQuery) {
//                             print("DEBUG: 10-second silence detected after speech, calling _stopListening.");
//                             _stopListening(); // This will trigger onStatus:notListening, leading to confirmation
//                             if (_chatState == ChatState.listeningQuery) {
//                                 if (_textController.text.isNotEmpty) {
//                                     _lastRecognizedWords = _textController.text;

//                                     // ✅ Add the user message BEFORE confirmation prompt
//                                     setState(() {
//                                         _messages.add(ChatMessage(
//                                         englishText: _lastRecognizedWords,
//                                         nativeText: _lastRecognizedWords,
//                                         isUser: true,
//                                         timestamp: DateTime.now(),
//                                         ));
//                                     });
//                                     _scrollToBottom();

//                                     // ✅ Ask for confirmation AFTER showing user message
//                                     _textController.clear();
//                                     _askForConfirmation(_lastRecognizedWords);
//                                 }
//                             } else if (_chatState == ChatState.awaitingConfirmation) {
//                                 // Mic stopped during confirmation listening (e.g., due to manual tap or external interruption)
//                                 // If the _speechActivityTimer for confirmation is NOT active, it means it wasn't a timeout,
//                                 // so we should re-prompt immediately. If it IS active, the timer will handle the re-prompt.
//                                 if (_speechActivityTimer == null || !_speechActivityTimer!.isActive) {
//                                     print("DEBUG: Mic stopped during confirmation (not by timeout), re-prompting.");
//                                     _speakText("Please give the confirmation. Say 'Yes' or 'No'.");
//                                     _startListeningForConfirmation(); // Restart listening for confirmation
//                                 }
//                             }
//                         }
//                         });
//                     }
//                 },
//                 onSoundLevelChange: (level) {
//                 // Optional: Add visual feedback for sound level if desired
//                 },
//                 listenFor: const Duration(minutes: 5), // Mic max time
//                 pauseFor: const Duration(seconds: 10), // Mic stays on longer during silence
//                 partialResults: true,
//             );
//             _speechActivityTimer?.cancel();
//             _speechActivityTimer = Timer(const Duration(seconds: 5), () async {
//             if (!userSpoke && _isListening && _chatState == ChatState.listeningQuery) {
//                 print("DEBUG: User did not speak within 5 seconds. Stopping mic.");
//                 _stopListening();
//                 setState(() {
//                 _chatState = ChatState.initial;
//                 _isListening = false;
//                 });
//                 final confirmationEnglish = "I didn't hear anything. Please tap the mic and try again.";
//                 final confirmationNative = await translateToNative(confirmationEnglish);
//                 _speakText(confirmationNative);
//                 //_addInitialWelcomeMessage();
//             }
//             });
//         } else if (_speech.isListening) {
//         print("Already listening (QR), no need to start again.");
//         } else if (!_speechAvailable) {
//         print("Speech recognition not available (QR).");
//         _speakText("Speech recognition is not available on your device.");
//         }
//     }

//     void _resetSilenceTimer() {
//         _speechActivityTimer?.cancel();
//         _speechActivityTimer = Timer(const Duration(seconds: 5), () {
//             if (_isListening && _chatState == ChatState.listeningQuery) {
//             print("⏱️ 5 seconds of silence. Stopping mic.");
//             _stopListening();
//             }
//         });
//     }

//     void _stopListening() async {
//         if (_speech.isListening) {
//         print("DEBUG: _stopListening: Calling _speech.stop().");
//         await _speech.stop(); // Stop the speech recognizer
//         }
//         _speechActivityTimer?.cancel(); // Cancel any active timer
//         // _isListening is intentionally NOT set to false here; it's handled in the onStatus callback
//         // to maintain state consistency with the plugin's actual status.
//     }

//     // --- API Call Functions ---

//     // Fetches all crops from the API
//     Future<List<Crop>> _fetchAllCrops() async {
//         try {
//         final response = await http.get(Uri.parse('$_apiBaseUrl/crops'));
//         if (response.statusCode == 200) {
//             List<dynamic> jsonList = json.decode(response.body);
//             return jsonList.map((json) => Crop.fromJson(json)).toList();
//         } else {
//             print('Failed to load crops: ${response.statusCode} ${response.body}');
//             return [];
//         }
//         } catch (e) {
//         print('Error fetching crops: $e');
//         return [];
//         }
//     }

//     // --- Query Handling Logic ---
//     // A simplified example of how to handle user queries.
//     // In a real application, this would involve more sophisticated NLP.
//     Future<String> _handleQuery(String englishQuery) async {
//         if (englishQuery.toLowerCase().contains('details of') ||
//             englishQuery.toLowerCase().contains('info about') ||
//             englishQuery.toLowerCase().contains('tell me about') ||
//             englishQuery.toLowerCase().contains('tell about')) {
//         final cropNameMatch = RegExp(r'(details of|info about|tell me about|tell about)\s+(\w+)').firstMatch(englishQuery.toLowerCase());
//         if (cropNameMatch != null && cropNameMatch.groupCount >= 2) {
//             final requestedCropName = cropNameMatch.group(2)!;
//             print('User requested details for crop: $requestedCropName');
//             return _getCropDetailsResponse(requestedCropName);
//         }
//         }

//         // Fallback to generic responses if no specific intent is matched
//         if (englishQuery.toLowerCase().contains('hello') || englishQuery.toLowerCase().contains('hi')) {
//         return "Hello there! How can I assist you?";
//         } else if (englishQuery.toLowerCase().contains('weather')) {
//         return "I can't provide real-time weather here, but your main screen has weather info!";
//         } else if (englishQuery.toLowerCase().contains('crop')) {
//         return "For general crop information, please use the 'Crop Info' button on the main screen. If you're looking for specific crop details, try asking 'details of [crop name]'.";
//         } else if (englishQuery.toLowerCase().contains('holiday')) {
//         return "You can check holidays using the 'Show Holidays' button on the main screen.";
//         } else if (englishQuery.toLowerCase().contains('market price')) {
//         return "Market prices can be viewed via the 'Market Prices' button on the main screen.";
//         } else {
//         return "You said: '$englishQuery'. I'm a simple chatbot for now. Try asking about weather, crops, or just say hello!";
//         }
//     }

//     Future<String> _getCropDetailsResponse(String requestedCropName) async {
//         final allCrops = await _fetchAllCrops();
//         final foundCrop = allCrops.firstWhere(
//         (crop) => crop.cropName.toLowerCase() == requestedCropName.toLowerCase(),
//         orElse: () => Crop(cropID: -1, cropName: 'Not Found', variety: '', plantType: ''), // Placeholder
//         );

//         if (foundCrop.cropID != -1) {
//         return "Here are the details for ${foundCrop.cropName}:\n"
//             "Variety: ${foundCrop.variety}\n"
//             "Plant Type: ${foundCrop.plantType}\n"
//             "Region: ${foundCrop.region ?? 'N/A'}\n";
//         } else {
//         return "I couldn't find any details for '$requestedCropName'. Please try another crop name.";
//         }
//     }

//     void _askForConfirmation(String nativeQuery) async {
//         setState(() {
//         _chatState = ChatState.awaitingConfirmation; // Set state for confirmation
//         });

//         final confirmationEnglish = "Do you want to search for this information? Say 'Yes' or 'No'.";
//         final confirmationNative = await translateToNative(confirmationEnglish);

//         // Add confirmation message to chat history (this is the assistant's message)
//         setState(() {
//         _messages.add(ChatMessage(
//             englishText: confirmationEnglish,
//             nativeText: confirmationNative,
//             isUser: false,
//             timestamp: DateTime.now(),
//         ));
//         });
//         await _speakText(confirmationNative);
//         _scrollToBottom();

//         // Automatically start listening for "Yes" or "No"
//         _startListeningForConfirmation();
//     }

//     void _startListeningForConfirmation() async {
//         // Ensure any previous listening session is stopped
//         await _speech.stop();
//         _speechActivityTimer?.cancel(); // Clear any lingering timers

//         if (_speechAvailable && !_speech.isListening) {
//         setState(() {
//             _isListening = true; // Mic on for confirmation
//         });
//         print("DEBUG: _startListeningForConfirmation: _isListening set to TRUE. Mic button should be RED. ChatState: awaitingConfirmation.");
//         print("Starting speech recognition for confirmation (QR)...");
//         _speech.listen(
//             localeId: getSpeechLocale(_currentLangCode),
//             listenMode: stt.ListenMode.dictation,
//             onResult: (result) async {
//             if (result.recognizedWords.trim().isNotEmpty) {
//                 final recognized = result.recognizedWords.toLowerCase();
//                 print("DEBUG: Confirmation recognized: $recognized");
//                 _textController.text = result.recognizedWords; // Show recognized confirmation in text box

//                 // Check for "Yes" variations including Kannada "ಹೌದು"
//                 if (recognized.contains('yes') || recognized.contains('yeah') || recognized.contains('sure') || recognized.contains('ಹೌದು')) {
//                 print("DEBUG: User said YES.");
//                 _stopListening(); // Stop confirmation listening
//                 _processConfirmedQuery();
//                 _textController.clear(); // Clear text box immediately after processing
//                 }
//                 // Check for "No" variations including Kannada "ಇಲ್ಲ"
//                 else if (recognized.contains('no') || recognized.contains('nope') || recognized.contains('nah') || recognized.contains('ಇಲ್ಲ')) {
//                 print("DEBUG: User said NO.");
//                 _stopListening(); // Stop confirmation listening
//                 _cancelQuery();
//                 _textController.clear(); // Clear text box immediately after processing
//                 } else {
//                 // If something else is said, re-prompt for confirmation
//                     final confirmationEnglish = "Please say 'Yes' or 'No'.";
//                     final confirmationNative = await translateToNative(confirmationEnglish);
//                 _speakText(confirmationNative);
//                 // Reset the timer as user spoke, even if not 'Yes'/'No'
//                 _speechActivityTimer?.cancel();
//                 _speechActivityTimer = Timer(const Duration(seconds: 15), () {
//                     if (_isListening && _chatState == ChatState.awaitingConfirmation) {
//                     print("DEBUG: No valid confirmation received within 15 seconds, re-asking.");
//                     _askForConfirmation(_lastRecognizedWords); // Re-ask for confirmation
//                     }
//                 });
//                 }
//             }
//             },
//             onSoundLevelChange: (level) {},
//                 pauseFor: const Duration(seconds: 10), // Mic stays on longer during silence
//                 cancelOnError: false,
//                 partialResults: true,
//         );
//         // Set a timeout for confirmation response (15 seconds).
//         // If this timer fires, it means no valid 'Yes'/'No' was heard within the period.
//         _speechActivityTimer = Timer(const Duration(seconds: 15), () {
//             if (_isListening && _chatState == ChatState.awaitingConfirmation) {
//             print("DEBUG: No confirmation received within 15 seconds, re-asking.");
//             _askForConfirmation(_lastRecognizedWords); // Re-ask for confirmation
//             }
//         });
//         } else if (_speech.isListening) {
//         print("Already listening for confirmation.");
//         } else if (!_speechAvailable) {
//         print("Speech recognition not available for confirmation.");
//         _speakText("Speech recognition is not available to confirm your query.");
//         _cancelQuery(); // Cancel if cannot listen for confirmation
//         }
//     }

//     void _processConfirmedQuery() async {
//         _speechActivityTimer?.cancel(); // Cancel any active timer
//         await _speech.stop(); // Ensure mic is off
//         setState(() {
//         _isListening = false; // Ensure mic button is off
//         _isSending = true; // Show loading indicator
//         _isMicEnabled = false; 
//         _chatState = ChatState.queryConfirmed; // Update state
//         });
//         print("DEBUG: _processConfirmedQuery: _isListening set to FALSE. Mic button should be GREY.");

//         _scrollToBottom();
//         _speakText(await translateToNative("Searching for the information...")); // Announce search

//         // Translate the confirmed query to English and handle it
//         final englishQueryForProcessing = await translateNativeToEnglish(_lastRecognizedWords);
//         final englishResponse = await _handleQuery(englishQueryForProcessing);
//         final nativeResponse = await translateToNative(englishResponse);

//         // Add response to chat history
//         setState(() {
//         _messages.add(ChatMessage(
//             englishText: englishResponse,
//             nativeText: nativeResponse,
//             isUser: false,
//             timestamp: DateTime.now(),
//         ));
//         _isSending = false; // Hide loading indicator
//         _chatState = ChatState.responseDisplayed; // Update state
//         _isMicEnabled = true; 
//         });

//         _speakText(nativeResponse); // Speak the response
//         _scrollToBottom();
//         //_addInitialWelcomeMessage(); // Prompt for next query
//     }

//     void _cancelQuery() async {
//         _speechActivityTimer?.cancel(); // Cancel any active timer
//         await _speech.stop(); // Ensure mic is off
//         setState(() {
//         _isListening = false; // Ensure mic button is off
//         _textController.clear();
//         _lastRecognizedWords = ''; // Clear the stored query
//         _chatState = ChatState.initial; // Reset to initial state
//         });
//         print("DEBUG: _cancelQuery: _isListening set to FALSE. Mic button should be GREY.");

//         // Display and speak the "query ended" message
//         final cancelEnglish = "Your query has been cancelled.";
//         final cancelNative = await translateToNative(cancelEnglish);
//         setState(() {
//         _messages.add(ChatMessage(
//             englishText: cancelEnglish,
//             nativeText: cancelNative,
//             isUser: false,
//             timestamp: DateTime.now(),
//         ));
//         });
//         _speakText(cancelNative);
//         _scrollToBottom();
//         //_addInitialWelcomeMessage(); // Prompt for next query
//     }

//     // Helper to scroll the chat to the latest message
//     void _scrollToBottom() {
//         WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (_scrollController.hasClients) {
//             _scrollController.animateTo(
//             _scrollController.position.maxScrollExtent,
//             duration: const Duration(milliseconds: 300),
//             curve: Curves.easeOut,
//             );
//         }
//         });
//     }

//     // Helper to speak text using TTS
//     Future<void> _speakText(String text) async {
//         await flutterTts.setLanguage(_currentLangCode);
//         await flutterTts.speak(text);
//     }

//     @override
//     Widget build(BuildContext context) {
//         return Scaffold(
//         appBar: AppBar(
//             title: const Text('Chat with Assistant'),
//             backgroundColor: Colors.blueAccent,
//         ),
//         body: Column(
//             children: [
//             Expanded(
//                 child: ListView.builder(
//                 controller: _scrollController,
//                 padding: const EdgeInsets.all(12.0),
//                 itemCount: _messages.length,
//                 itemBuilder: (context, index) {
//                     final message = _messages[index];
//                     return _buildMessageBubble(message);
//                 },
//                 ),
//             ),
//             // Show loading indicator when sending query
//             if (_isSending)
//                 const Padding(
//                 padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
//                 child: Align(
//                     alignment: Alignment.centerLeft,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                 ),
//                 ),
//             _buildMessageInput(),
//             ],
//         ),
//         );
//     }

//     // Builds a single chat message bubble
//     Widget _buildMessageBubble(ChatMessage message) {
//         final alignment =
//             message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
//         final color = message.isUser ? Colors.blue[100] : Colors.grey[200];
//         final textColor = Colors.black87; // Consistent text color
//         final borderRadius = message.isUser
//             ? const BorderRadius.only(
//                 topLeft: Radius.circular(15),
//                 bottomLeft: Radius.circular(15),
//                 bottomRight: Radius.circular(15),
//             )
//             : const BorderRadius.only(
//                 topRight: Radius.circular(15),
//                 bottomLeft: Radius.circular(15),
//                 bottomRight: Radius.circular(15),
//             );

//         return Container(
//         margin: const EdgeInsets.symmetric(vertical: 6.0),
//         child: Column(
//             crossAxisAlignment: alignment,
//             children: [
//             Row(
//                 mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                 // Speaker icon for assistant messages
//                 if (!message.isUser)
//                     IconButton(
//                     icon: const Icon(Icons.volume_up, size: 20),
//                     color: Colors.blueGrey,
//                     onPressed: () => _speakText(message.nativeText),
//                     padding: EdgeInsets.zero,
//                     constraints: const BoxConstraints(),
//                     ),
//                 Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
//                     decoration: BoxDecoration(
//                     color: color,
//                     borderRadius: borderRadius,
//                     boxShadow: [
//                         BoxShadow(
//                         color: Colors.black.withOpacity(0.1),
//                         blurRadius: 3,
//                         offset: const Offset(0, 2),
//                         ),
//                     ],
//                     ),
//                     constraints: BoxConstraints(
//                     maxWidth: MediaQuery.of(context).size.width * 0.75,
//                     ),
//                     child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                         // English text
//                         Text(
//                         message.englishText,
//                         style: TextStyle(color: textColor, fontSize: 16.0),
//                         ),
//                         // Native text if different from English
//                         if (message.englishText != message.nativeText)
//                         Padding(
//                             padding: const EdgeInsets.only(top: 4.0),
//                             child: Text(
//                             message.nativeText,
//                             style: TextStyle(
//                                 color: textColor.withOpacity(0.7),
//                                 fontSize: 14.0,
//                                 fontStyle: FontStyle.italic),
//                             ),
//                         ),
//                     ],
//                     ),
//                 ),
//                 ],
//             ),
//             // Timestamp for the message
//             Padding(
//                 padding: const EdgeInsets.only(top: 4.0, right: 8.0, left: 8.0),
//                 child: Text(
//                 '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
//                 style: TextStyle(color: Colors.grey[600], fontSize: 10.0),
//                 ),
//             ),
//             ],
//         ),
//         );
//     }

//     // Builds the input area with microphone and confirmation buttons
//     Widget _buildMessageInput() {
//         return Container(
//         padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
//         decoration: BoxDecoration(
//             color: Theme.of(context).cardColor,
//             boxShadow: [
//             BoxShadow(
//                 color: Colors.black.withOpacity(0.1),
//                 blurRadius: 5,
//                 offset: const Offset(0, -3),
//             ),
//             ],
//         ),
//         child: Row(
//             crossAxisAlignment: CrossAxisAlignment.end,
//             children: [
//             Expanded(
//                 child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                 decoration: BoxDecoration(
//                     color: Colors.grey[100],
//                     borderRadius: BorderRadius.circular(24),
//                 ),
//                 child: Row(
//                     children: [
//                     Expanded(
//                         child: TextField(
//                         controller: _textController,
//                         decoration: const InputDecoration(
//                             hintText: 'Speak ...',
//                             border: InputBorder.none,
//                         ),
//                         style: const TextStyle(fontSize: 14),
//                         maxLines: 3,
//                         keyboardType: TextInputType.multiline,
//                         textCapitalization: TextCapitalization.sentences,
//                         readOnly: true, // Make text box non-editable, only displays recognized speech
//                         ),
//                     ),
//                     ],
//                 ),
//                 ),
//             ),
//             const SizedBox(width: 8.0),
//             // Mic button for Start/Stop
//             FloatingActionButton(
//                 heroTag: 'mic_control_qr', // Unique tag for Hero animations
//                 mini: true, // Smaller button
//                 backgroundColor: _isListening ? Colors.red : Colors.grey, // Red when listening, grey when not
//                 onPressed:  _isMicEnabled
//                     ? () {
//                     if (_isListening) {
//                     _stopListening();
//                     } else {
//                     _startListening();
//                     }
//                     }
//                     : null, // Disable button when mic is disabled
//                 child: Icon(
//                 _isListening ? Icons.mic : Icons.mic_off, // Change icon based on listening state
//                 size: 28,
//                 ),
//             ),
//             // Removed Conditional buttons for confirmation (Yes/No)
//             ],
//         ),
//         );
//     }
//     }