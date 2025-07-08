import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

// --- API Configuration ---
const String _apiBaseUrl = 'http://172.23.176.1:3000/api'; // Use 10.0.2.2 for Android Emulator to access host localhost

// 1. Data Model for a Chat Message
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

// 2. Data Model for Crop (matches your SQL table structure)
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

  const QueryResponseScreen({Key? key, required this.initialLangCode}) : super(key: key);

  @override
  _QueryResponseScreenState createState() => _QueryResponseScreenState();
}

class _QueryResponseScreenState extends State<QueryResponseScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isLocked = false;
  bool _isPaused = false;
  double _initialY = 0.0;
  bool _speechAvailable = false;
  late FlutterTts flutterTts;

  bool _isSending = false;

  late String _currentLangCode;

  @override
  void initState() {
    super.initState();
    _currentLangCode = widget.initialLangCode;

    flutterTts = FlutterTts();
    _initTts();

    _speech = stt.SpeechToText();
    _initSpeechRecognizer();

    _addInitialWelcomeMessage();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage(_currentLangCode);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _initSpeechRecognizer() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      print("Microphone permission not granted for QueryResponseScreen.");
      return;
    }

    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        print("Speech status (QR): $status (isListening: $_isListening, isLocked: $_isLocked, isPaused: $_isPaused)");
        if (status == 'notListening') {
          if (_isLocked && !_isPaused) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (!_speech.isListening && !_isPaused && _isLocked) {
                print("Auto-restarting listening (QR - locked mic).");
                _startListening();
              }
            });
          } else if (!_isLocked) {
            _stopListening();
          }
        } else if (status == 'listening') {
          setState(() {
            _isListening = true;
          });
          print("Successfully listening (QR).");
        }
      },
      onError: (error) {
        print("Speech error (QR): $error");
        setState(() {
          _isListening = false;
          if (!_isLocked) {
            _stopListening();
          }
        });
      },
    );
    print("Speech recognizer initialized (QR): $_speechAvailable");
  }

  Future<void> _addInitialWelcomeMessage() async {
    final welcomeEnglish = "Hello! How can I help you today?";
    final welcomeNative = await translateToNative(welcomeEnglish);
    setState(() {
      _messages.add(ChatMessage(
        englishText: welcomeEnglish,
        nativeText: welcomeNative,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
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
      default: return TranslateLanguage.english;
    }
  }

  Future<String> translateToNative(String text) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(_currentLangCode),
      );
      final translated = await translator.translateText(text);
      await translator.close();
      return translated;
    } catch (e) {
      print("❌ Translation to native failed: $e");
      return text;
    }
  }

  Future<String> translateNativeToEnglish(String nativeText) async {
    try {
      final modelManager = OnDeviceTranslatorModelManager();
      final isModelDownloaded = await modelManager.isModelDownloaded('en');
      if (!isModelDownloaded) {
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
      return nativeText;
    }
  }

  String getSpeechLocale(String langCode) {
    switch (langCode) {
      case 'hi': return 'hi-IN';
      case 'kn': return 'kn-IN';
      case 'ta': return 'ta-IN';
      case 'te': return 'te-IN';
      case 'ml': return 'ml-IN';
      case 'mr': return 'mr-IN';
      case 'bn': return 'bn-IN';
      case 'gu': return 'gu-IN';
      case 'ur': return 'ur-IN';
      default: return 'en-IN';
    }
  }

  void _startListening() async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        print("Microphone permission not granted.");
        return;
      }
    }

    if (_speechAvailable && !_speech.isListening) {
      setState(() {
        _isListening = true;
        _isPaused = false;
      });
      print("Starting speech recognition (QR)...");
      _speech.listen(
        localeId: getSpeechLocale(_currentLangCode),
        listenMode: stt.ListenMode.dictation,
        onResult: (result) async {
          if (result.recognizedWords.trim().isNotEmpty) {
            final nativeText = result.recognizedWords;
            setState(() {
              if (_textController.text.isEmpty) {
                _textController.text = nativeText;
              } else {
                _textController.text = "${_textController.text} $nativeText";
              }
            });
          }
        },
        onSoundLevelChange: (level) {
          // print("Sound level (QR): $level");
        },
      );
    } else if (_speech.isListening) {
      print("Already listening (QR), no need to start again.");
    } else if (!_speechAvailable) {
      print("Speech recognition not available (QR).");
    }
  }

  void _stopListening() async {
    if (_speech.isListening) {
      print("Stopping speech recognition (QR)...");
      await _speech.stop();
    }
    setState(() {
      _isListening = false;
      _isLocked = false;
      _isPaused = false;
    });
  }

  // --- API Call Functions ---

  // Fetches all crops from the API
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
  Future<String> _handleQuery(String englishQuery) async {
    // Simple keyword-based intent recognition
    if (englishQuery.toLowerCase().contains('details of') ||
        englishQuery.toLowerCase().contains('info about') ||
        englishQuery.toLowerCase().contains('tell me about') || 
        englishQuery.toLowerCase().contains('tell about')) {
      final cropNameMatch = RegExp(r'(details of|info about|tell me about|tell about)\s+(\w+)').firstMatch(englishQuery.toLowerCase());
      if (cropNameMatch != null && cropNameMatch.groupCount >= 2) {
        final requestedCropName = cropNameMatch.group(2)!;
        print('User requested details for crop: $requestedCropName');
        return _getCropDetailsResponse(requestedCropName);
      }
    }

    // Fallback to generic responses if no specific intent is matched
    if (englishQuery.toLowerCase().contains('hello') || englishQuery.toLowerCase().contains('hi')) {
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
      orElse: () => Crop(cropID: -1, cropName: 'Not Found', variety: '', plantType: ''), // Placeholder for not found
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


  void _sendMessage() async {
    final nativeInputText = _textController.text.trim();
    if (nativeInputText.isEmpty) return;

    final englishQuery = await translateNativeToEnglish(nativeInputText);

    setState(() {
      _messages.add(ChatMessage(
        englishText: englishQuery,
        nativeText: nativeInputText,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _textController.clear();
      _stopListening();
      _isSending = true; // Start loading indicator
    });

    _scrollToBottom();

    // Handle the query and get the response
    final englishResponse = await _handleQuery(englishQuery);
    final nativeResponse = await translateToNative(englishResponse);

    setState(() {
      _messages.add(ChatMessage(
        englishText: englishResponse,
        nativeText: nativeResponse,
        isUser: false,
        timestamp: DateTime.now(),
      ));
      _isSending = false; // Hide loading indicator
    });

    _scrollToBottom();
  }

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

  Future<void> _speakText(String text) async {
    await flutterTts.setLanguage(_currentLangCode);
    await flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Assistant'),
        backgroundColor: Colors.blueAccent,
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

  Widget _buildMessageBubble(ChatMessage message) {
    final alignment =
        message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = message.isUser ? Colors.blue[100] : Colors.grey[200];
    final textColor = message.isUser ? Colors.black87 : Colors.black87;
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
            mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!message.isUser)
                IconButton(
                  icon: const Icon(Icons.volume_up, size: 20),
                  color: Colors.blueGrey,
                  onPressed: () => _speakText(message.nativeText),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
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
                    Text(
                      message.englishText,
                      style: TextStyle(color: textColor, fontSize: 16.0),
                    ),
                    if (message.englishText != message.nativeText)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          message.nativeText,
                          style: TextStyle(
                              color: textColor.withOpacity(0.7),
                              fontSize: 14.0,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Speak or type...',
                        border: InputBorder.none,
                      ),
                      style: TextStyle(fontSize: 14),
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isListening && !_isLocked)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            '⬆️ Slide up to lock',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      if (_isLocked)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            '🔒 Locked',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      GestureDetector(
                        onTapDown: (details) {
                          _initialY = details.localPosition.dy;
                          if (!_isListening && !_isLocked) {
                            _startListening();
                          } else if (_isPaused) {
                            print("Resuming listening from tap down (previously paused).");
                            _startListening();
                          }
                        },
                        onTapUp: (details) {
                          if (!_isLocked && _isListening) {
                            _stopListening();
                          }
                        },
                        onLongPress: () {
                          if (!_isLocked) {
                            setState(() => _isLocked = true);
                            print("Mic locked via long press.");
                            _startListening();
                          }
                        },
                        onPanUpdate: (details) {
                          final dy = details.localPosition.dy - _initialY;
                          if (dy < -30 && !_isLocked) {
                            setState(() => _isLocked = true);
                            print("Mic locked via slide up gesture.");
                            _startListening();
                          }
                        },
                        onPanEnd: (_) {
                          if (!_isLocked && _isListening) {
                            _stopListening();
                          }
                        },
                        child: Icon(
                          _isListening || _isLocked ? Icons.mic : Icons.mic_none,
                          color: _isListening || _isLocked ? Colors.red : Colors.grey,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((_isListening || _isLocked) && _textController.text.isNotEmpty) ...[
                FloatingActionButton(
                  heroTag: 'send_qr',
                  mini: true,
                  backgroundColor: Colors.green,
                  onPressed: _isSending ? null : _sendMessage,
                  child: _isSending
                      ? const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
                        )
                      : const Icon(Icons.send, size: 18),
                ),
                const SizedBox(height: 5),
                FloatingActionButton(
                  heroTag: 'cancel_qr',
                  mini: true,
                  onPressed: () {
                    _stopListening();
                    setState(() {
                      _textController.clear();
                    });
                  },
                  child: const Icon(Icons.delete, size: 18),
                ),
                const SizedBox(height: 5),
                FloatingActionButton(
                  heroTag: 'play_pause_resume_qr',
                  mini: true,
                  backgroundColor: Colors.blueAccent,
                  onPressed: () async {
                    if (_isPaused) {
                      print("Resuming listening (QR)...");
                      _startListening();
                    } else {
                      print("Pausing listening (QR)...");
                      await _speech.stop();
                      setState(() {
                        _isListening = false;
                        _isPaused = true;
                      });
                    }
                  },
                  child: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 18),
                ),
              ] else if (_textController.text.isNotEmpty) ...[
                FloatingActionButton(
                  heroTag: 'send_typed_qr',
                  mini: true,
                  backgroundColor: Colors.green,
                  onPressed: _isSending ? null : _sendMessage,
                  child: _isSending
                      ? const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
                        )
                      : const Icon(Icons.send, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speech.stop();
    _speech.cancel();
    flutterTts.stop();
    super.dispose();
  }
}
