import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:flutter/rendering.dart'; // Required for RenderAbstractViewport
import '../api/pageapi.dart';

class CropPreparationScreen extends StatefulWidget {
  final String langCode;

  const CropPreparationScreen({Key? key, required this.langCode}) : super(key: key);

  @override
  State<CropPreparationScreen> createState() => _CropPreparationScreenState();
}

class _CropPreparationScreenState extends State<CropPreparationScreen> {
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
  final GlobalKey _scrollKey = GlobalKey();


  @override
  void initState() {
    super.initState();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final translated = await translateToNative(currentPrompt);
      await flutterTts.speak(translated);
    });
  PageAPI.logPageVisit("PreSowingPreparationScreen");
  }

  @override
  void dispose() {
    _speech.stop();
    flutterTts.stop();
    super.dispose();
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
      case 'hi': return TranslateLanguage.hindi;
      case 'kn': return TranslateLanguage.kannada;
      case 'ta': return TranslateLanguage.tamil;
      case 'te': return TranslateLanguage.telugu;
      case 'mr': return TranslateLanguage.marathi;
      case 'bn': return TranslateLanguage.bengali;
      case 'gu': return TranslateLanguage.gujarati;
      case 'ur': return TranslateLanguage.urdu;
      default: return TranslateLanguage.english;
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
            final spokenText = result.recognizedWords.toLowerCase();
            final translated = await translateNativeToEnglish(spokenText);
            print("translated spoken : $translated");
            if (translated.trim().toLowerCase() != "tomato") {
              final err = await translateToNative("Only 'tomato' is supported currently");
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

            await fetchPreparationSteps("tomato");
          }
        },
      );
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
Future<void> fetchPreparationSteps(String crop) async {
  final url = Uri.parse("https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/api/preparation/$crop");
  final response = await http.get(url);

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final steps = data['steps'] as List<dynamic>;

    if (steps.isEmpty) {
      final msg = await translateToNative("No steps found.");
      setState(() {
        preparationSteps = msg;
        showPreparation = true;
      });
      await flutterTts.speak(msg);
      return;
    }

    final englishList = <String>[];
    final nativeList = <String>[];

    for (var step in steps) {
      final englishText = "${step['StepOrder']}. ${step['StepTitle']}: ${step['StepDescription']}";
      final nativeText = await translateToNative(englishText);
      englishList.add(englishText);
      nativeList.add(nativeText);
    }

    setState(() {
      englishSteps = englishList.join("\n");
      nativeSteps = nativeList.join("\n");
      showPreparation = true;
      isSpeaking = true;
    });

    await flutterTts.speak(nativeList.join(". "));
  } else {
    final err = await translateToNative("Failed to fetch preparation steps.");
    await flutterTts.speak(err);
  }
}
List<Widget> _buildStepList(String englishSteps, String nativeSteps) {
  final englishLines = englishSteps.split('\n');
  final nativeLines = nativeSteps.split('\n');
  final widgets = <Widget>[];

  for (int i = 0; i < englishLines.length; i++) {
    final en = englishLines[i];
    final native = i < nativeLines.length ? nativeLines[i] : '';
    widgets.add(Text(en, style: const TextStyle(fontWeight: FontWeight.bold)));
    widgets.add(Text("($native)", style: const TextStyle(color: Colors.black87)));
    widgets.add(const SizedBox(height: 10));
  }

  return widgets;
}

String _getVisibleText() {
  try {
    final renderBox = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
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
        final maxVisibleOffset = scrollOffset + scrollable.position.viewportDimension;

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
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<String>(
          future: translateToNative("Pre Sowing"),
          builder: (context, snapshot) {
            final native = snapshot.data ?? "Pre Sowing";
            return Text("Pre Sowing\n($native)");
          },
        ),
      ),
body: Padding(
  padding: const EdgeInsets.all(20.0),
  child: showPreparation
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: _scrollKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: translateToNative("Steps"),
                      builder: (context, snapshot) {
                        final nativeLabel = snapshot.data ?? "Steps";
                        return Text(
                          "📝 Steps ($nativeLabel):",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    ..._buildStepList(englishSteps, nativeSteps),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
  child: IconButton(
    icon: Icon(isSpeaking ? Icons.pause : Icons.volume_up, size: 36),
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
  ),
),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              future: translateToNative(currentPrompt),
              builder: (context, snapshot) {
                return Text(
                  "$currentPrompt\n(${snapshot.data ?? ''})",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                );
              },
            ),
            const SizedBox(height: 20),
            _buildField("Crop Name", cropName ?? ""),
            if (hasValidationError && errorMessage != null)
              Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
              ),
          ],
        ),
),
      floatingActionButton: showPreparation
    ? null
    : FloatingActionButton(
        onPressed: () {
          if (isListening) {
            _speech.stop();
            setState(() => isListening = false);
          } else {
            startListening();
          }
        },
        backgroundColor: isListening ? Colors.red : Colors.grey,
        child: Icon(isListening ? Icons.mic : Icons.mic_off, size: 30),
      ),
    );
  }

  Widget _buildField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value.isEmpty ? '-' : value),
        ),
      ],
    );
  }
}
