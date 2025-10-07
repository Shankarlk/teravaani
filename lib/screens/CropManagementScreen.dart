import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:teravaani/main.dart';
import 'package:teravaani/route_observer.dart';
import 'package:teravaani/screens/query_response_screen.dart';
import 'diagnosisScreen.dart';
import 'post_harvesting_screen.dart';
import 'crop_preparation_screen.dart';
import 'calendar_screen.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CropManagementScreen extends StatefulWidget {
  final String langCode;

  const CropManagementScreen({Key? key, required this.langCode})
    : super(key: key);

  @override
  State<CropManagementScreen> createState() => _CropManagementScreenState();
}

class _CropManagementScreenState extends State<CropManagementScreen>
    with WidgetsBindingObserver, RouteAware {
  String lblTitle = "Crop Management";
  String lblDiagnose = "Diagnose Plant";
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  String lblPreHarvest = "Pre Sowing Preparation";
  String lblPostHarvest = "Post Harvesting";
  String lblCrop = "Crop Guide";
  String deviceId = "";
  bool _hasInternet = true;
  bool _isSpeaking = false;
  late String lblPreHarvestNative;
  late String lblDiagnoseNative;
  late String lblPostHarvestNative;
  late String lblCropNative;
  final FlutterTts _flutterTts = FlutterTts();
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
    _flutterTts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTranslations();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is minimized / backgrounded
      _flutterTts.stop();
      setState(() => _isSpeaking = false);
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

  Future<void> _speakContent() async {
    await _flutterTts.stop();
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
    } else {
      // Speak only native-language labels
      String content =
          """
      $lblPreHarvestNative
      $lblDiagnoseNative
      $lblPostHarvestNative
      $lblCropNative
    """;

      setState(() => _isSpeaking = true);

      // Make speak() await completion reliably
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.speak(content);

      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _initTranslations() async {
    lblTitle = await _withNativeTranslation("Crop Management", widget.langCode);
    lblDiagnose = await _withNativeTranslation(
      "Diagnose Plant",
      widget.langCode,
    );
    lblPostHarvest = await _withNativeTranslation(
      "Post Harvesting",
      widget.langCode,
    );
    lblPreHarvest = await _withNativeTranslation(
      "Pre Sowing Preparation",
      widget.langCode,
    );
    lblCrop = await _withNativeTranslation("Crop Guide", widget.langCode);

    lblTitle = await _withNativeTranslation("Crop Management", widget.langCode);
    lblPreHarvestNative = await _translateToNativeLanguage(
      "Pre Sowing Preparation",
      widget.langCode,
    );
    lblDiagnoseNative = await _translateToNativeLanguage(
      "Diagnose Plant",
      widget.langCode,
    );
    lblPostHarvestNative = await _translateToNativeLanguage(
      "Post Harvesting",
      widget.langCode,
    );
    lblCropNative = await _translateToNativeLanguage(
      "Crop Guide",
      widget.langCode,
    );
    setState(() {});
    _speakContent();
  }

  Future<String> _withNativeTranslation(
    String englishText,
    String targetLangCode,
  ) async {
    final cleanedText = englishText.replaceAll('_', ' ');
    final native = await _translateToNativeLanguage(
      cleanedText,
      targetLangCode,
    );
    return "$cleanedText\n($native)";
  }

  Future<String> _translateToNativeLanguage(
    String text,
    String targetLangCode,
  ) async {
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
      widget.langCode,
    );
    final almsg = await _translateToNativeLanguage("Alert", widget.langCode);
    final okmsg = await _translateToNativeLanguage("OK", widget.langCode);

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
      await _flutterTts.speak(msg); // 🔊 Speak the message
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flutterTts.stop();
    super.dispose();
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
  void didPopNext() {
    super.didPopNext();
    Future.delayed(const Duration(milliseconds: 500), () {
      _speakContent();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // When back is pressed → go to CropManagementScreen instead of Home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => VoiceHomePage()),
        );
        return false; // Prevent default pop
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // space between logo and text
              // 📝 App Name
              Expanded(
                child: Text(
                  lblTitle,
                  style: const TextStyle(
                    color: Colors.white, // set title text color to white
                    fontWeight: FontWeight.w700, // optional: make it bold
                    fontSize: 20, // optional: adjust size
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Image.asset(
                "assets/logo.png", // your image path
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
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMenuCard(
                icon: FontAwesomeIcons.seedling,
                label: lblPreHarvest,
                onTap: () {
                  _flutterTts.stop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CropPreparationScreen(langCode: widget.langCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                icon: Icons.science,
                label: lblDiagnose,
                onTap: () {
                  _flutterTts.stop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          DiagnosisScreen(widtargetLangCode: widget.langCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                icon: Icons.local_florist,
                label: lblPostHarvest,
                onTap: () {
                  _flutterTts.stop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PostHarvestingScreen(langCode: widget.langCode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                icon: Icons.agriculture,
                label: lblCrop,
                onTap: () async {
                  _flutterTts.stop();
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
              ),
            ],
          ),
        ),
        // 2️⃣ Add floatingActionButton inside Scaffold
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: "speakerBtn",
              backgroundColor: _isSpeaking ? Colors.grey : Colors.blue,
              onPressed: _speakContent,
              child: Icon(
                _isSpeaking ? Icons.pause : Icons.volume_up,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            FloatingActionButton(
              heroTag: "micBtn",
              backgroundColor: Colors.green,
              onPressed: () {
                _flutterTts.stop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        QueryResponseScreen(initialLangCode: widget.langCode),
                  ),
                );
              },
              child: const Icon(Icons.mic, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12), // adjust size
                decoration: BoxDecoration(
                  color: Colors.green, // circular background
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
