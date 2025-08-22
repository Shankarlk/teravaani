import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../database/database_helper.dart';
import 'package:permission_handler/permission_handler.dart';
import './capture_screen.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../route_observer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'no_internet_widget.dart';
import 'dart:async';
import '../api/pageapi.dart';


class DiagnosisScreen extends StatefulWidget {
    final String widtargetLangCode;
    const DiagnosisScreen({Key? key, required this.widtargetLangCode}) : super(key: key);
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
  String _imageUrl ='';
  String lblDiagnosis ='Diagnosis';
  List<dynamic> _history = [];
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
    final uri = Uri.parse('https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/predict');
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
  routeObserver.unsubscribe(this);
  super.dispose();
}

@override
void didPopNext() {
  // Called when coming back to this screen
  print("Returned to DiagnosisScreen. Reloading history.");
  _loadHistory();
}



  Future<void> _sendImageForPrediction(File imageFile) async {
    final uri = Uri.parse('https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/predict'); // Replace with your IP
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

    final spoken = "I think your plant has $label with $confidence percent confidence";

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
  Future<String> _translateToNativeLanguage(String text, String targetLangCode) async {
    final OnDeviceTranslator translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: TranslateLanguage.values.firstWhere((lang) => lang.bcpCode == targetLangCode),
    );
    print("native language: $targetLangCode");
    return await translator.translateText(text);
  }
  Future<void> _speakFullResult(String diagnosis, String symptoms, List<Map<String, String>> chemicalProducts, List<String> organicTreatments, String targetLangCode) async {
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
    final translatedText = await _translateToNativeLanguage(fullText, targetLangCode);

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
  final uri = Uri.parse('https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/getpredictions?deviceId=$deviceId');

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed to load history")),
    );
  }
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
    _chemicalProducts = List<Map<String, dynamic>>.from(responseJson['chemical_products'] ?? []);
    _organicTreatments = List<String>.from(responseJson['organic_treatments'] ?? []);
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
Future<String> _withNativeTranslation(String englishText, String langCode) async {
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
  _connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
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
  lblDiagnosis = await _withNativeTranslation(lblDiagnosis,targetLangCode);
  setState(() {}); // update UI after translation
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
      title: Text(lblDiagnosis),
      actions: [
        IconButton(
          iconSize: 35.0,
          icon: Icon(Icons.camera_alt),
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
                    return ListTile(
                      leading: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              width: 50,
                              height: 50,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.broken_image),
                            )
                          : const Icon(Icons.image_not_supported),
                      title: FutureBuilder<String>(
                        future: _withNativeTranslation(label, targetLangCode),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.done &&
                              snapshot.hasData) {
                            return Text(snapshot.data!);
                          } else {
                            return Text(label); // fallback while loading
                          }
                        },
                      ),
                      subtitle: Text(""),
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
                          print("Returned from CaptureScreen with .then()");
                          _loadHistory();
                        });
                      },
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
  );
}
}
