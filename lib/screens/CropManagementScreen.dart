import 'package:flutter/material.dart';
import 'diagnosisScreen.dart';
import 'post_harvesting_screen.dart';
import 'crop_preparation_screen.dart';
import 'calendar_screen.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'no_internet_widget.dart';
import 'dart:async';

class CropManagementScreen extends StatefulWidget {
  final String langCode;

  const CropManagementScreen({Key? key, required this.langCode}) : super(key: key);

  @override
  State<CropManagementScreen> createState() => _CropManagementScreenState();
}

class _CropManagementScreenState extends State<CropManagementScreen> {
  String lblTitle = "Crop Management";
  String lblDiagnose = "Diagnose Plant";
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  String lblPreHarvest = "Pre Sowing Preparation";
  String lblPostHarvest = "Post Harvesting";
  String lblCrop = "View Crop Calendar";
  String deviceId = "";
bool _hasInternet = true;
  @override
  void initState() {
    super.initState();
  _connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
    setState(() {
      _hasInternet = result != ConnectivityResult.none;
    });
  });
    _initTranslations();
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

  Future<void> _initTranslations() async {
    lblTitle = await _withNativeTranslation("Crop Management", widget.langCode);
    lblDiagnose = await _withNativeTranslation("Diagnose Plant", widget.langCode);
    lblPostHarvest = await _withNativeTranslation("Post Harvesting", widget.langCode);
    lblPreHarvest = await _withNativeTranslation("Pre Sowing Preparation", widget.langCode);
    lblCrop = await _withNativeTranslation("View Crop Calendar", widget.langCode);
    setState(() {});
  }

  Future<String> _withNativeTranslation(String englishText, String targetLangCode) async {
    final cleanedText = englishText.replaceAll('_', ' ');
    final native = await _translateToNativeLanguage(cleanedText, targetLangCode);
    return "$cleanedText\n($native)";
  }

  Future<String> _translateToNativeLanguage(String text, String targetLangCode) async {
    final OnDeviceTranslator translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.values.firstWhere(
        (lang) => lang.bcpCode == targetLangCode,
        orElse: () => TranslateLanguage.hindi, // fallback
      ),
    );
    return await translator.translateText(text);
  }
Future<void> _checkInternetConnection() async {
  final connectivityResult = await Connectivity().checkConnectivity();
  setState(() {
    _hasInternet = connectivityResult != ConnectivityResult.none;
  });
}

  @override
  Widget build(BuildContext context) {
    
  if (!_hasInternet) {
    return NoInternetScreen(
      onRetry: _checkInternetConnection, // calls the same method
    );
  }
    return Scaffold(
      appBar: AppBar(
        title: Text(lblTitle, textAlign: TextAlign.center),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CropPreparationScreen(langCode: widget.langCode),
                      ),
                    );
                  },
                  child: Text(lblPreHarvest, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DiagnosisScreen(widtargetLangCode: widget.langCode),
                      ),
                    );
                  },
                  child: Text(lblDiagnose, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PostHarvestingScreen(langCode: widget.langCode),
                      ),
                    );
                  },
                  child: Text(lblPostHarvest, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(height: 16), 
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  onPressed: () async {
                    final id = await getOrCreateDeviceId();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CalendarScreen(
                          userId: id,
                          targetLangCode: widget.langCode,
                        ),
                      ),
                    );
                  },
                  child: Text(lblCrop, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
