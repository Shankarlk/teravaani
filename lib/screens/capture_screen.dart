import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../database/database_helper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'no_internet_widget.dart';
import '../api/pageapi.dart';
import 'dart:async';

class CaptureScreen extends StatefulWidget {
  final String targetLangCode;
  final Map<String, dynamic>? existingRecord;
  final File? localImageFile; // 👈 add this
  final bool predictionFailed;
  String _translatedText = '';
  bool _isSpeaking = false;
  bool _isPaused = false;

  CaptureScreen({
    Key? key,
    required this.targetLangCode,
    this.existingRecord,
    this.localImageFile,
    this.predictionFailed = false,
  }) : super(key: key);

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  File? _image;
  String? _diagnosis;
  bool _isLoading = false;
  String? _symptoms;
  List<dynamic>? _chemicalProducts;
  List<dynamic>? _organicTreatments;
  final FlutterTts flutterTts = FlutterTts();
  late String targetLangCode;
  String _imageUrl = '';
  String _translatedText = '';
  String lblDiagnosis = 'Diagnosis Details';
  String lblSymptoms = 'Symptoms';
  String lblChemical = 'Chemical Treatments';
  String lblOrganic = 'Organic Remedies';
  bool _isSpeaking = false;
  bool _isPaused = false;
  bool _hasInternet = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
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
    WidgetsBinding.instance.addObserver(this);
    targetLangCode = widget.targetLangCode;

    _initTranslations();
    if (widget.existingRecord != null) {
      _loadExistingRecord(widget.existingRecord!);
    }
    if (widget.predictionFailed) {
      faileddiagnosis();
      print("failed diagonsis");
    }
    flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    });

    PageAPI.logPageVisit("DiagnosisDetailsScreen");
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
    final msg = await _translateToNativeLanguage(
      "No Internet Connection. Please check your connection and try again.",
      targetLangCode,
    );
    final almsg = await _translateToNativeLanguage("Alert", targetLangCode);
    final okmsg = await _translateToNativeLanguage("OK", targetLangCode);

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

  Future<void> _initTranslations() async {
    lblSymptoms = await _withNativeTranslation(lblSymptoms);
    lblChemical = await _withNativeTranslation(lblChemical);
    lblOrganic = await _withNativeTranslation(lblOrganic);
    lblDiagnosis = await _withNativeTranslation(lblDiagnosis);
    setState(() {}); // update UI after translation
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

  Future<String> _withNativeTranslation(String englishText) async {
    print(targetLangCode);
    final cleanedText = englishText.replaceAll('_', ' ');
    final native = await _translateToNativeLanguage(
      cleanedText,
      targetLangCode,
    );
    return "$cleanedText\n($native)";
  }

  void _loadExistingRecord(Map<String, dynamic> record) async {
    print('existing: ${record}');

    final response = record['response'] as Map<String, dynamic>;
    final englishtxt = response['label'].replaceAll('_', ' ');
    final symptomsText = response['symptoms'] ?? '';

    final chemicalList = (response['chemical_products'] as List<dynamic>?)?.map(
      (e) {
        final item = Map<String, dynamic>.from(e as Map);
        return {
          'name': item['name']?.toString() ?? '',
          'company': item['company']?.toString() ?? '',
          'content': item['content']?.toString() ?? '',
          'dosage': item['dosage']?.toString() ?? '',
          'approx_cost': item['approx_cost']?.toString() ?? '', // <- Fix here
        };
      },
    ).toList();

    final organicList =
        (response['organic_treatments'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final translatedDiagnosis = await _withNativeTranslation(englishtxt);
    final translatedSymptoms = await _withNativeTranslation(symptomsText);

    // Translate each chemical product's name field
    List<Map<String, String>> translatedChemicalList = [];
    if (chemicalList != null) {
      for (var item in chemicalList) {
        final name = item['name'] ?? '';
        final translatedName = await _withNativeTranslation(name);
        final company = await _withNativeTranslation(item['company'] ?? '');
        final content = await _withNativeTranslation(item['content'] ?? '');
        final dosage = await _withNativeTranslation(item['dosage'] ?? '');
        final approx_cost = await _withNativeTranslation(
          item['approx_cost'] ?? '',
        );
        translatedChemicalList.add({
          'name': translatedName,
          'company': company,
          'content': content,
          'dosage': dosage,
          'approx_cost': approx_cost,
        });
      }
    }

    // Translate each organic treatment string
    List<String> translatedOrganicList = [];
    for (var item in organicList) {
      final translatedItem = await _withNativeTranslation(item);
      translatedOrganicList.add(translatedItem);
    }

    setState(() {
      _diagnosis = translatedDiagnosis;
      _symptoms = translatedSymptoms;
      _chemicalProducts = translatedChemicalList;
      _organicTreatments = translatedOrganicList;
      _imageUrl = record['imageUrl'] ?? '';
      _isLoading = false;
    });
    final speaktranslatedDiagnosis = await translateToNative(englishtxt);
    final speaktranslatedSymptoms = await translateToNative(symptomsText);

    await _speakFullResult(
      speaktranslatedDiagnosis,
      speaktranslatedSymptoms,
      translatedChemicalList,
      translatedOrganicList,
      targetLangCode,
    );
  }
  
  Future<String> translateToNative(String englishText) async {
    print(targetLangCode);
    final cleanedText = englishText.replaceAll('_', ' ');
    final native = await _translateToNativeLanguage(
      cleanedText,
      targetLangCode,
    );
    return "$native";
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
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Select from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);

    if (picked != null) {
      setState(() {
        _image = File(picked.path);
        _diagnosis = null;
        _isLoading = true;
      });
      print('response picked searching image ${picked.path}');
      await _sendImageForPrediction(File(picked.path));
    }
  }

  Future<void> _sendImageForPrediction(File imageFile) async {
    final uri = Uri.parse(
      'http://172.20.10.5:3000/api/predict',
    ); // Replace with your IP
    final deviceId = await getOrCreateDeviceId();
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', imageFile.path))
      ..fields['deviceId'] = deviceId;

    final response = await request.send();
    final result = await response.stream.bytesToString();
    print('response image:- ${result}');

    if (response.statusCode != 200) {
      final errorData = json.decode(result);
      final errorMessage = errorData['error'] ?? 'Unknown error occurred';
      final details = errorData['details'] ?? '';
      _translatedText = await _translateToNativeLanguage(
        "The diagnosis failed.",
        targetLangCode,
      );
      final predictionS = await _withNativeTranslation("The diagnosis failed.");
      await flutterTts.speak(_translatedText);
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
      setState(() {
        _diagnosis = "❌ ${predictionS}";
        _symptoms = " ";
        _chemicalProducts = [];
        _organicTreatments = [];
        _isLoading = false;
      });
      return;
    }
    final jsonData = json.decode(result);
    final label = jsonData['label'];
    final symptomsText = jsonData['symptoms'] ?? '';
    final chemicalList = (jsonData['chemical_products'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final organicList = (jsonData['organic_treatments'] as List<dynamic>? ?? [])
        .cast<String>();

    final translatedDiagnosis = await _withNativeTranslation(label);
    final translatedSymptoms = await _withNativeTranslation(symptomsText);

    List<Map<String, String>> translatedChemicalList = [];
    for (var item in chemicalList) {
      final name = item['name'] ?? '';
      final company = item['company'] ?? '';
      final content = item['content'] ?? '';
      final dosage = item['dosage'] ?? '';
      final approxCost = item['approx_cost'] ?? '';

      final translatedName = await _withNativeTranslation(name);
      final translatedCompany = await _withNativeTranslation(company);
      final translatedContent = await _withNativeTranslation(content);
      final translatedDosage = await _withNativeTranslation(dosage);
      final translatedCost = await _withNativeTranslation(approxCost);

      translatedChemicalList.add({
        'name': translatedName,
        'company': translatedCompany,
        'content': translatedContent,
        'dosage': translatedDosage,
        'approx_cost': translatedCost,
      });
    }
    List<String> translatedOrganicList = [];
    for (var item in organicList) {
      final translatedItem = await _withNativeTranslation(item);
      translatedOrganicList.add(translatedItem);
    }

    setState(() {
      _diagnosis = translatedDiagnosis;
      _symptoms = translatedSymptoms;
      _chemicalProducts = translatedChemicalList;
      _organicTreatments = translatedOrganicList;
      _isLoading = false;
    });

    //await _saveToHistory(_diagnosis!);
    await _speakFullResult(
      _diagnosis ?? "No diagnosis found",
      _symptoms ?? "No symptoms available",
      (_chemicalProducts ?? []).cast<Map<String, String>>(),
      (_organicTreatments ?? []).cast<String>(),
      targetLangCode,
    );
  }
  
/// Show AlertDialog for Service Unavailable
void _showServiceUnavailableDialog() async {
  final msg = await _translateToNativeLanguage(
    "Service is currently unavailable. Please try again later.",
    targetLangCode,
  );
  final almsg = await _translateToNativeLanguage("Alert", targetLangCode);
  final okmsg = await _translateToNativeLanguage("OK", targetLangCode);

  if (mounted) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Alert\n($almsg)"),
        content: Text("Service is currently unavailable. Please try again later.\n($msg)"),
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

    await flutterTts.speak(msg); // 🔊 Speak error message
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

    _translatedText = await _translateToNativeLanguage(
      fullText,
      targetLangCode,
    );
    await flutterTts.setLanguage(targetLangCode);
    await flutterTts.setSpeechRate(0.5);

    _speak();
  }

  Future<void> _speak() async {
    await flutterTts.speak(_translatedText);
    setState(() {
      _isSpeaking = true;
      _isPaused = false;
    });
  }

  Future<void> _pause() async {
    await flutterTts.pause();
    setState(() {
      _isPaused = true;
      _isSpeaking = false;
    });
  }

  Future<void> _resume() async {
    await flutterTts.pause();
    setState(() {
      _isSpeaking = true;
      _isPaused = false;
    });
  }

  Future<void> _stop() async {
    await flutterTts.stop();
    setState(() {
      _isSpeaking = false;
      _isPaused = false;
    });
  }

  void faileddiagnosis() async {
    String failedMsg = "❌ Diagnosis Failed.";
    String translated = await _translateToNativeLanguage(
      "Diagnosis Failed.",
      targetLangCode,
    );
    setState(() {
      _diagnosis = "$failedMsg\n($translated)";
      _translatedText = translated;
    });

    flutterTts.speak(translated);
  }

  @override
  void dispose() {
    _stop(); // Stop TTS on back
    flutterTts.stop();
    _connectivitySubscription.cancel();
    super.dispose();
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

    return await translator.translateText(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // 📝 Title
            Expanded(
              child: Text(
                lblDiagnosis,
                style: const TextStyle(
                  color: Colors.white, // white text color
                  fontWeight: FontWeight.w700, // bold
                  fontSize: 18, // adjust as needed
                ),
              ),
            ),

            const SizedBox(width: 20),

            // 🌱 Logo Image
            Image.asset(
              "assets/logo.png", // same logo as other screens
              height: 70,
              fit: BoxFit.contain,
            ),
          ],
        ),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(
          color: Colors.white, // back button color
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔲 Card for Image
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Center(
                  child: _image != null
                      ? Image.file(
                          _image!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : _imageUrl.isNotEmpty
                      ? Image.network(
                          _imageUrl,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : const Icon(
                          Icons.image_not_supported,
                          size: 100,
                          color: Colors.grey,
                        ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 🔲 Card for Diagnosis Text + Treatments
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _diagnosis ?? "No diagnosis",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_symptoms != null && _symptoms!.trim().isNotEmpty) ...[
                      Text("${lblSymptoms} : $_symptoms"),
                      const SizedBox(height: 12),
                    ],

                    if ((_chemicalProducts?.isNotEmpty ?? false)) ...[
                      Text(
                        "${lblChemical} :",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._chemicalProducts!.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            "• ${e['name']} by ${e['company']} "
                            "(${e['content']}, dosage: ${e['dosage']}, cost: ${e['approx_cost']})",
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if ((_organicTreatments?.isNotEmpty ?? false)) ...[
                      Text(
                        "${lblOrganic} :",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._organicTreatments!.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text("• $e"),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: _isSpeaking ? Colors.grey : Colors.blue,
        child: Icon(
          _isSpeaking ? Icons.pause : Icons.volume_up,
          color: Colors.white,
        ),
        onPressed: () {
          if (_isSpeaking) {
            _pause();
          } else if (_isPaused) {
            _speak(); // use _speak() instead of _resume()
          } else {
            _speak();
          }
        },
      ),
    );
  }
}
