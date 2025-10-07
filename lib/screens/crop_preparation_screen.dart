import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:flutter/rendering.dart'; // Required for RenderAbstractViewport
import 'package:teravaani/screens/CropManagementScreen.dart';
import '../api/pageapi.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CropPreparationScreen extends StatefulWidget {
  final String langCode;
  final String? cropName;

  const CropPreparationScreen({required this.langCode, this.cropName});

  @override
  State<CropPreparationScreen> createState() => _CropPreparationScreenState();
}

class _CropPreparationScreenState extends State<CropPreparationScreen>
    with WidgetsBindingObserver {
  final FlutterTts flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool isListening = false;
  String? cropName;
  String? preparationSteps;
  String currentPrompt = "Please say the crop name";
  bool hasValidationError = false;
  String? errorMessage;
  bool showPreparation = false;
  String nativeSteps = "";
  String englishSteps = "";
  bool isSpeaking = false;
  bool isErrorOrNoSteps = false;
  final GlobalKey _scrollKey = GlobalKey();
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
    _initTts();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.cropName != null && widget.cropName!.isNotEmpty) {
        // 👇 Auto-fetch if cropName provided
        setState(() {
          cropName = widget.cropName;
        });
        await fetchPreparationSteps(widget.cropName!);
      } else {
        final translated = await translateToNative(currentPrompt);
        await flutterTts.speak(translated);
      }
    });
    PageAPI.logPageVisit("PreSowingPreparationScreen");
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
    _speech.stop();
    flutterTts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is minimized / backgrounded
        flutterTts.stop();
        setState(() => isSpeaking = false);
    }
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage(widget.langCode);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
  }

  Future<String> translateToNative(String text) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(widget.langCode),
      );
      final translated = await translator.translateText(text);
      await translator.close();
      return translated;
    } catch (_) {
      return text;
    }
  }

  Future<String> translateNativeToEnglish(String text) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: _getMLKitLanguage(widget.langCode),
        targetLanguage: TranslateLanguage.english,
      );
      final translated = await translator.translateText(text);
      await translator.close();
      return translated;
    } catch (_) {
      return text;
    }
  }

  TranslateLanguage _getMLKitLanguage(String code) {
    switch (code) {
      case 'hi':
        return TranslateLanguage.hindi;
      case 'kn':
        return TranslateLanguage.kannada;
      case 'ta':
        return TranslateLanguage.tamil;
      case 'te':
        return TranslateLanguage.telugu;
      case 'mr':
        return TranslateLanguage.marathi;
      case 'bn':
        return TranslateLanguage.bengali;
      case 'gu':
        return TranslateLanguage.gujarati;
      case 'ur':
        return TranslateLanguage.urdu;
      default:
        return TranslateLanguage.english;
    }
  }

  Future<void> startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => isListening = true);
      _speech.listen(
        localeId: getSpeechLocale(widget.langCode),
        listenMode: stt.ListenMode.deviceDefault,
        onResult: (result) async {
          if (result.finalResult) {
            _speech.stop();
            setState(() => isListening = false);
            final spokenText = result.recognizedWords.toLowerCase();
            final translated = await translateNativeToEnglish(spokenText);
            print("translated spoken : $translated");
            if (translated.trim().toLowerCase() != "tomato") {
              final err = await translateToNative(
                "Only 'tomato' is supported currently",
              );
              setState(() {
                errorMessage = err;
                hasValidationError = true;
              });
              await flutterTts.speak(err);
              return;
            }

            setState(() {
              cropName = spokenText;
              hasValidationError = false;
              errorMessage = null;
            });

            await fetchPreparationSteps(translated);
          }
        },
      );
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

  Future<void> fetchPreparationSteps(String crop) async {
    try {
      final url = Uri.parse("http://172.20.10.5:3000/api/preparation/$crop");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final steps = data['steps'] as List<dynamic>;

        if (steps.isEmpty) {
          final msg = await translateToNative("No steps found.");
          setState(() {
            preparationSteps = msg;
            showPreparation = true;
            isErrorOrNoSteps = true;
          });
          await flutterTts.speak(msg);
          return;
        }

        final englishList = <String>[];
        final nativeList = <String>[];

        for (var step in steps) {
          final englishText =
              "${step['StepOrder']}. ${step['StepTitle']}: ${step['StepDescription']}";
          final nativeText = await translateToNative(englishText);
          englishList.add(englishText);
          nativeList.add(nativeText);
        }

        setState(() {
          englishSteps = englishList.join("\n");
          nativeSteps = nativeList.join("\n");
          showPreparation = true;
          isSpeaking = true;
          isErrorOrNoSteps = false;
        });

        await flutterTts.speak(nativeList.join(". "));
      } else {
        final err = await translateToNative(
          "Failed to fetch preparation steps.",
        );
        setState(() {
          preparationSteps = "Failed to fetch preparation steps.\n($err)";
          showPreparation = true;
          isErrorOrNoSteps = true;
        });
        await flutterTts.speak(err);
      }
    } catch (e) {
      final err = await translateToNative(
        "Service unavailable. Please try again later.",
      );
      final almsg = await translateToNative("Alert");
      final okmsg = await translateToNative("ok");
      setState(() {
        preparationSteps = err;
        showPreparation = false;
        isErrorOrNoSteps = true;
      });
      await flutterTts.speak(err);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("Alert\n($almsg)"),
            content: Text(
              "Service unavailable. Please try again later.\n($err)",
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
    }
  }

  List<Widget> _buildStepList(String englishSteps, String nativeSteps) {
    final englishLines = englishSteps.split('\n');
    final nativeLines = nativeSteps.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < englishLines.length; i++) {
      final en = englishLines[i].trim();
      final native = i < nativeLines.length ? nativeLines[i].trim() : '';

      // Skip empty lines
      if (en.isEmpty && native.isEmpty) continue;

      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              en,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              "($native)",
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
            const SizedBox(height: 10),

            // Add HR line
            const Divider(color: Colors.grey, thickness: 1),
            const SizedBox(height: 10),
          ],
        ),
      );
    }

    return widgets;
  }

  String _getVisibleText() {
    try {
      final renderBox =
          _scrollKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return "";

      final scrollable = Scrollable.of(_scrollKey.currentContext!);
      final viewport = RenderAbstractViewport.of(renderBox);

      final visibleTextBuffer = StringBuffer();
      List<Element> children = [];
      _scrollKey.currentContext!.visitChildElements((element) {
        children.add(element);
      });

      for (final element in children) {
        final render = element.renderObject;
        if (render is RenderBox && scrollable != null && viewport != null) {
          final offset = viewport.getOffsetToReveal(render, 0.0).offset;
          final scrollOffset = scrollable.position.pixels;
          final maxVisibleOffset =
              scrollOffset + scrollable.position.viewportDimension;

          if (offset >= scrollOffset && offset <= maxVisibleOffset) {
            final widget = element.widget;
            if (widget is Text) {
              visibleTextBuffer.writeln(widget.data);
            }
          }
        }
      }

      return visibleTextBuffer.toString();
    } catch (_) {
      return nativeSteps;
    }
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
            future: translateToNative("Pre Sowing"),
            builder: (context, snapshot) {
              final native = snapshot.data ?? "Pre Sowing";
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 📝 Title (English + Native)
                  Expanded(
                    child: Text(
                      "Pre Sowing\n($native)",
                      style: const TextStyle(
                        color: Colors.white, // set title text color to white
                        fontWeight: FontWeight.w700, // bold text
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
              // 🔹 Prompt + Crop Field inside card
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
                      _buildField("Crop Name", cropName ?? "e.g., Tomato"),
                      if (hasValidationError && errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 🔹 Steps card (visible only after API fetch)
              // 🔹 Steps card (visible only after API fetch)
              if (showPreparation)
                Expanded(
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SingleChildScrollView(
                        key: _scrollKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const FaIcon(
                                  FontAwesomeIcons.seedling,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 8),
                                FutureBuilder<String>(
                                  future: translateToNative("Steps"),
                                  builder: (context, snapshot) {
                                    final nativeLabel =
                                        snapshot.data ?? "Steps";
                                    return Text(
                                      "Steps ($nativeLabel):",
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._buildStepList(englishSteps, nativeSteps),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min, // shrink row to content
          children: [
            // 🔊 Speaker button (visible only if steps available)
            if (showPreparation)
              FloatingActionButton(
                heroTag: "speakBtn",
                onPressed: () async {
                  if (isSpeaking) {
                    await flutterTts.stop();
                    setState(() => isSpeaking = false);
                  } else {
                    final visibleText = _getVisibleText();
                    if (visibleText.isNotEmpty) {
                      setState(() => isSpeaking = true);
                      await flutterTts.speak(visibleText);
                      flutterTts.setCompletionHandler(() {
                        setState(() => isSpeaking = false);
                      });
                    }
                  }
                },
                backgroundColor: isSpeaking ? Colors.grey : Colors.blue,
                child: Icon(
                  isSpeaking ? Icons.pause : Icons.volume_up,
                  size: 24,
                ),
              ),

            const SizedBox(width: 12), // space between buttons
            // 🎤 Mic button (always visible)
            FloatingActionButton(
              heroTag: "micBtn",
              onPressed: () {
                if (isListening) {
                  _speech.stop();
                  setState(() => isListening = false);
                } else {
                  setState(() => showPreparation = false);
                  startListening();
                }
              },
              backgroundColor: isListening ? Colors.red : Colors.green,
              child: Icon(isListening ? Icons.mic : Icons.mic_off, size: 24),
            ),
          ],
        ),
      ),
    );
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
}
