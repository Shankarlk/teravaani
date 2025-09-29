import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import './capture_screen.dart';
import '../route_observer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'no_internet_widget.dart';
import 'dart:async';
import '../api/pageapi.dart';

class DiagnosisScreen extends StatefulWidget {
  final String widtargetLangCode;

  const DiagnosisScreen({required this.widtargetLangCode});
  @override
  _DiagnosisScreenState createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> with RouteAware {
  File? _image;
  String? _diagnosis;
  bool _isLoading = false;
  String? _symptoms;
  List<dynamic>? _chemicalProducts;
  List<dynamic>? _organicTreatments;
  final FlutterTts flutterTts = FlutterTts();
  late String targetLangCode;
  String _imageUrl = '';
  String lblDiagnosis = 'Diagnose Plant';
  List<dynamic> _history = [];
  bool _isSpeaking = false;
  String? _latestRecordText; 
  Future<void> _pickImageAndNavigate(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);

    if (picked != null) {
      setState(() {
        _isLoading = true;
      });

      final prediction = await _sendImageAndGetResponse(File(picked.path));

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CaptureScreen(
            targetLangCode: targetLangCode,
            existingRecord: prediction,
            localImageFile: File(picked.path), // 👈 new param
            predictionFailed: prediction == null, // 👈 new param
          ),
        ),
      ).then((_) {
        _loadHistory();
      });

      setState(() {
        _isLoading = false;
      });
    }
  }

  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  Future<Map<String, dynamic>?> _sendImageAndGetResponse(File imageFile) async {
    try {
      final uri = Uri.parse('http://172.20.10.5:3000/predict');
      final deviceId = await getOrCreateDeviceId();
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('image', imageFile.path))
        ..fields['deviceId'] = deviceId;

      final response = await request.send();
      final result = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonData = json.decode(result);
        _loadHistory();
        return {
          'label': jsonData['label'],
          'confidence': jsonData['confidence'],
          'imageUrl': jsonData['imageUrl'],
          'response': jsonData,
        };
        print("Prediction image: $jsonData['imageUrl']");
      } else {
        _loadHistory();
        print("Prediction failed: $result");
        return null;
      }
    } catch (e) {
      print("Error in prediction: $e");
      return null;
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

  void _prepareLatestRecordForSpeech() async {
  if (_history.isNotEmpty) {
    String allText = "";

    for (var record in _history) {
      final label = record['label'] ?? 'Unknown';
      final confidence = (record['confidence'] ?? 0.0) * 100;

      String englishText = "$label";

      String nativeText = "";
      try {
        nativeText = await _withNativeTranslation(label, targetLangCode);
        // Only show native text if chemical or organic list is not empty
        final responseJson = record['response'] is String
            ? json.decode(record['response'])
            : record['response'] ?? {};

        final chemicalProducts = List<Map<String, dynamic>>.from(
            responseJson['chemical_products'] ?? []);
        final organicTreatments =
            List<String>.from(responseJson['organic_treatments'] ?? []);

        if (chemicalProducts.isNotEmpty || organicTreatments.isNotEmpty) {
          englishText += "\n($nativeText)";
        }
      } catch (e) {
        print("Translation failed: $e");
      }

      allText += "$englishText\n\n"; // separate each record
    }

    setState(() {
      _latestRecordText = allText.trim();
    });
  } else {
    _latestRecordText = null;
  }
}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    flutterTts.stop();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadHistory();
  }

  Future<void> _sendImageForPrediction(File imageFile) async {
    final uri = Uri.parse(
      'http://172.20.10.5:3000/predict',
    ); // Replace with your IP
    final deviceId = await getOrCreateDeviceId();
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', imageFile.path))
      ..fields['deviceId'] = deviceId;

    final response = await request.send();
    final result = await response.stream.bytesToString();
    print('response image:- ${result}');
    final jsonData = json.decode(result);
    final label = jsonData['label'];
    final confidence = (jsonData['confidence'] * 100).toStringAsFixed(2);

    final spoken =
        "I think your plant has $label with $confidence percent confidence";

    setState(() {
      _diagnosis = "$label (Confidence: $confidence%)";
      _symptoms = jsonData['symptoms'];
      _chemicalProducts = jsonData['chemical_products'];
      _organicTreatments = jsonData['organic_treatments'];
      _isLoading = false;
    });

    await _saveToHistory(_diagnosis!);
    await _speakFullResult(
      _diagnosis ?? "No diagnosis found",
      _symptoms ?? "No symptoms available",
      (_chemicalProducts ?? []).cast<Map<String, String>>(),
      (_organicTreatments ?? []).cast<String>(),
      targetLangCode,
    );
  }

  Future<String> _translateToNativeLanguage(
    String text,
    String targetLangCode,
  ) async {
    final OnDeviceTranslator translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.values.firstWhere(
        (lang) => lang.bcpCode == targetLangCode,
      ),
    );
    print("native language: $targetLangCode");
    return await translator.translateText(text);
  }

  Future<void> _speakFullResult(
    String diagnosis,
    String symptoms,
    List<Map<String, String>> chemicalProducts,
    List<String> organicTreatments,
    String targetLangCode,
  ) async {
    String fullText = "$diagnosis.\nSymptoms: $symptoms.\n";

    if (chemicalProducts.isNotEmpty) {
      fullText += "Chemical Treatments:\n";
      for (var product in chemicalProducts) {
        fullText +=
            "• ${product['name']} by ${product['company']}, contains ${product['content']}, dosage: ${product['dosage']}, cost: ${product['approx_cost']}.\n";
      }
    }

    if (organicTreatments.isNotEmpty) {
      fullText += "Organic Remedies:\n";
      for (var remedy in organicTreatments) {
        fullText += "• $remedy.\n";
      }
    }

    // Translate fullText to native language (e.g., Hindi, Kannada, etc.)
    final translatedText = await _translateToNativeLanguage(
      fullText,
      targetLangCode,
    );

    await flutterTts.setLanguage(targetLangCode); // e.g., 'hi' for Hindi
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak(translatedText);
  }

  Future<void> _saveToHistory(String result) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('diagnosis_history') ?? [];
    history.add("${DateTime.now()}: $result");
    await prefs.setStringList('diagnosis_history', history);
  }

  Future<void> _loadHistory() async {
    final deviceId = await getOrCreateDeviceId(); // or hardcoded for testing
    final uri = Uri.parse(
      'http://172.20.10.5:3000/getpredictions?deviceId=$deviceId',
    );

    try {
      final response = await http.get(uri);
      final history = json.decode(response.body) as List<dynamic>;
      print('history:- ${history}');
      setState(() {
        _history = history;
      });

      if (history.isNotEmpty) {
        final latest = history.last;
        _updateDiagnosisFromRecord(latest);
      }
    } catch (e) {
      print("Error fetching history: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to load history")));
    }
    _prepareLatestRecordForSpeech();
  }

  void _updateDiagnosisFromRecord(dynamic record) {
    final label = record['label'] ?? 'Unknown';
    final confidence = (record['confidence'] ?? 0.0) * 100;
    final imageUrl = record['imageUrl'];
    final responseJson = record['response'] is String
        ? json.decode(record['response'])
        : record['response'] ?? {};

    setState(() {
      _diagnosis = "$label (Confidence: ${confidence.toStringAsFixed(2)}%)";
      _symptoms = responseJson['symptoms'] ?? "No symptoms provided.";
      _chemicalProducts = List<Map<String, dynamic>>.from(
        responseJson['chemical_products'] ?? [],
      );
      _organicTreatments = List<String>.from(
        responseJson['organic_treatments'] ?? [],
      );
      _image = null;
      _imageUrl = imageUrl ?? '';
    });
  }

  Future<void> _showImageSourceDialog() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Capture from Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageAndNavigate(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Select from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageAndNavigate(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _withNativeTranslation(
    String englishText,
    String langCode,
  ) async {
    print(targetLangCode);
    final cleanedText = englishText.replaceAll('_', ' ');
    final native = await _translateToNativeLanguage(cleanedText, langCode);
    return "$cleanedText\n($native)";
  }

  bool _hasInternet = true;
  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
    _loadHistory();
    targetLangCode = widget.widtargetLangCode;
    _initTranslations();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      setState(() {
        _hasInternet = result != ConnectivityResult.none;
      });
    });
    PageAPI.logPageVisit("DiagnosisHistoryScreen");
  }

  Future<void> _checkInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _hasInternet = connectivityResult != ConnectivityResult.none;
    });
  }

  Future<void> _initTranslations() async {
    lblDiagnosis = await _withNativeTranslation(lblDiagnosis, targetLangCode);
    setState(() {}); // update UI after translation
  }

Future<void> _speakLatestRecord() async {
  if (_latestRecordText == null) return;

  if (_isSpeaking) {
    await flutterTts.stop();
    setState(() => _isSpeaking = false);
  } else {
    setState(() => _isSpeaking = true);

    await flutterTts.setLanguage(targetLangCode);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.awaitSpeakCompletion(true);
    await flutterTts.speak(_latestRecordText!);

    setState(() => _isSpeaking = false);
  }
}

  @override
  Widget build(BuildContext context) {
    if (!_hasInternet) {
      return NoInternetScreen(
        onRetry: () {
          _checkInternetConnection();
        },
      );
    }

    if (!_hasInternet) {
      return NoInternetScreen(
        onRetry: _checkInternetConnection, // calls the same method
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          lblDiagnosis,
          style: const TextStyle(
            color: Colors.white, // set title text color to white
            fontWeight: FontWeight.w700, // optional: make it bold
            fontSize: 20, // optional: adjust size
          ),
        ),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(
          color: Colors.white, // back button color
        ),
        actions: [
          IconButton(
            iconSize: 35.0,
            icon: Icon(Icons.camera_alt_outlined),
            color: Colors.white,
            onPressed: _showImageSourceDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          _history.isEmpty
              ? const Center(child: Text("No history found."))
              : Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final record = _history[index];
                      final label = record['label'] ?? 'Unknown';
                      final confidence = (record['confidence'] ?? 0.0) * 100;
                      final imageUrl = record['imageUrl'];

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null
                                ? Image.network(
                                    imageUrl,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.broken_image,
                                              color: Colors.redAccent,
                                            ),
                                  )
                                : const Icon(
                                    Icons.image_not_supported,
                                    color: Colors.grey,
                                  ),
                          ),
                          title: FutureBuilder<String>(
                            future: _withNativeTranslation(
                              label,
                              targetLangCode,
                            ),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                      ConnectionState.done &&
                                  snapshot.hasData) {
                                return Text(
                                  snapshot.data!,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              } else {
                                return Text(label); // fallback while loading
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CaptureScreen(
                                  targetLangCode: targetLangCode,
                                  existingRecord: record,
                                ),
                              ),
                            ).then((_) {
                              _loadHistory(); // reload when returning
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),

          // Full screen loader overlay
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text(
                      '',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _latestRecordText != null
    ? FloatingActionButton(
        heroTag: "speakerBtn",
        backgroundColor: _isSpeaking ? Colors.grey : Colors.blue,
        onPressed: _speakLatestRecord,
        child: Icon(
          _isSpeaking ? Icons.pause : Icons.volume_up,
          color: Colors.white,
        ),
      )
    : null,

    );
  }
}
