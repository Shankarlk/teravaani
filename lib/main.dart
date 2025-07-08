import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import './database/database_helper.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import './crop_info_screen.dart';
import './screens/holiday_list_screen.dart';
import './screens/market_price_screen.dart'; 
import './screens/address_list_screen.dart'; 
import './screens/query_response_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().db;

  runApp(MaterialApp(
    home: VoiceHomePage(),
    debugShowCheckedModeBanner: false,
  ));
}

class VoiceHomePage extends StatefulWidget {
  @override
  _VoiceHomePageState createState() => _VoiceHomePageState();
}

class _VoiceHomePageState extends State<VoiceHomePage> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _text = 'Tap the mic to start speaking...';
  String _weatherInfo = 'Weather info loading...';
  List<String> _forecast = [];
  String? _locationMessage;
  final FlutterTts flutterTts = FlutterTts();
  String _langCode = 'en';
  String titleText = 'Speak Now';
  String continueText = 'Continue';
  String titleApp = 'Voice to Text';
  String locationFetchingText = 'Fetching location...';
  String weatherLabel = 'Weather';
  String forecastLabel = '7-Day Forecast';
  String recentLogsLabel = 'Recent Voice Logs';
  bool _showTranscriptionBox = false;
  TextEditingController _textController = TextEditingController();
  bool _showFullForecast = false;
  bool _speechAvailable = false;
  String? _userDistrict;
  String? _userState;
  bool _isLocked = false;
  bool _isPaused = false;
  double _initialY = 0.0;



  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _requestPermissions().then((_) async {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          print("Speech status: $status (isListening: $_isListening, isLocked: $_isLocked, isPaused: $_isPaused)");
          if (status == 'notListening') {
            if (_isLocked && !_isPaused) {
              print("Attempting auto-restart due to notListening (locked mic).");
              Future.delayed(Duration(milliseconds: 500), () {
                if (!_speech.isListening && !_isPaused && _isLocked) {
                  print("Auto-restarting listening (condition met).");
                  _startListening();
                } else {
                  print("Auto-restart condition not met (isListening: ${_speech.isListening}, isPaused: $_isPaused, isLocked: $_isLocked).");
                }
              });
            } else if (!_isLocked) {
              print("Explicitly stopping listening (not locked).");
              _stopListening();
            }
          } else if (status == 'listening') {
            setState(() {
              _isListening = true;
            });
            print("Successfully listening.");
          }
        },
        onError: (error) => print("Speech error: $error"),
      );  

      final locale = await _speech.systemLocale();
      final allLocales = await _speech.locales();
      print("🎤 Default system locale: $locale");
      print("🌐 Available locales: $allLocales");
    });
    flutterTts.setSpeechRate(0.5); // optional
    flutterTts.setPitch(1.0);
  }

  Future<void> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    print("🎙️ Microphone: $micStatus");

    final locStatus = await Permission.locationWhenInUse.request();
    print("📍 Location: $locStatus");

    if (locStatus.isGranted) {
      _getLocation(); // Only call after permission granted
    } else {
      setState(() {
        _locationMessage = "Location permission not granted.";
      });
    }
  }

  Future<void> _translateUILabels() async {
    titleApp = 'Voice to Text\n(${await translateToNative('Voice to Text')})';
    locationFetchingText = 'Fetching location...\n(${await translateToNative('Fetching location...')})';
    weatherLabel = 'Weather\n(${await translateToNative('Weather')})';
    forecastLabel = '7-Day Forecast\n(${await translateToNative('7-Day Forecast')})';
    recentLogsLabel = 'Recent Voice Logs\n(${await translateToNative('Recent Voice Logs')})';

    setState(() {}); // Refresh UI
  }

  Future<void> _getLocation() async {
    final savedSettings = await DatabaseHelper().getUserSettings();
    if (savedSettings != null) {
      print("📦 Loaded location from DB");
      final state = savedSettings['state'];
      final district = savedSettings['district'];
      final lang = savedSettings['language'];

      setState(() {
        _locationMessage = "$district, $state";
        _langCode = lang;
        _userDistrict = district;
        _userState = state;
      });

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

      await _translateStaticLabels(_langCode);
      await _translateUILabels();
      return;
    }

    // 👇 Fallback to device location if not stored yet
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationMessage = "Location services disabled.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationMessage = "Location permissions permanently denied.");
        return;
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final state = placemark.administrativeArea ?? '';
          final district = placemark.subAdministrativeArea ?? placemark.locality ?? '';
          final langCode = getLanguageCodeFromState(state);

          await DatabaseHelper().insertOrUpdateUserSettings(
            language: langCode,
            state: state,
            district: district,
          );

          setState(() {
            _locationMessage = "$district, $state";
            _langCode = langCode;
            _userDistrict = district;
            _userState = state;
          });

          await _getWeather(position.latitude, position.longitude);
          await _translateStaticLabels(langCode);
          await _translateUILabels();
        }
      }
    } catch (e) {
      print("❌ Error fetching location: $e");
      setState(() => _locationMessage = "Error fetching location.");
    }
  }

  String getLanguageCodeFromState(String? state) {
    switch (state?.toLowerCase()) {
      case 'karnataka':
        return 'kn'; // Kannada
      case 'uttar pradesh':
        return 'hi'; // Hindi
      case 'tamil nadu':
        return 'ta'; // Tamil
      default:
        return 'en'; // Fallback to English
    }
  }

  Future<String> translateText(String text, String targetLangCode) async {
    try {
      final sourceLang = TranslateLanguage.english;
      final targetLang = _getMLKitLanguage(targetLangCode);

      final modelManager = OnDeviceTranslatorModelManager();

      // ✅ Use .bcpCode to convert enum to string
      final isModelDownloaded = await modelManager.isModelDownloaded(targetLang.bcpCode);
      print("🟡 Model download started for ${targetLang.bcpCode}");

      if (!isModelDownloaded) {
        await modelManager.downloadModel(targetLang.bcpCode, isWifiRequired: false);
      }

      final translator = OnDeviceTranslator(
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
      );

      final translatedText = await translator.translateText(text);
      await translator.close();
      return translatedText;
    } catch (e) {
      print("❌ Translation failed: $e");
      return text;
    }
  }

  Future<void>  _translateStaticLabels(String langCode) async {
    final translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _getMLKitLanguage(langCode),
    );

    final translatedTitle = await translator.translateText('Speak Now');
    final translatedContinue = await translator.translateText('Continue');

    await translator.close();

    setState(() {
      titleText = 'Speak Now\n($translatedTitle)';
      continueText = 'Continue\n($translatedContinue)';
    });
    _langCode = langCode;
    await flutterTts.setLanguage(langCode);
    //await flutterTts.speak(translatedTitle); 
  }

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
      return TranslateLanguage.english;
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
        sourceLanguage: _getMLKitLanguage(_langCode),
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

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) => print("Speech status: $status"),
        onError: (error) => print("Speech error: $error"),
      );
      if (available) {
      await Future.delayed(Duration(milliseconds: 300));
      setState(() => _isListening = true);
      _speech.listen(
        localeId: getSpeechLocale(_langCode),
        onResult: (result) async {
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            final nativeText = result.recognizedWords;
            final englishText = await translateNativeToEnglish(nativeText);

            setState(() {
              _text = "$nativeText\n(English: $englishText)";
              _textController.text += (_textController.text.isEmpty ? '' : ' ') + nativeText;
              _showTranscriptionBox = true;
              });
            } else {
              print("🟡 No speech detected or empty result");
            }
          },
        );
      }
    }
  }

  Future<void> _getWeather(double lat, double lon) async {
    try {
      
      final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&daily=weathercode,temperature_2m_max,relative_humidity_2m_max,windspeed_10m_max'
      '&timezone=auto',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List dates = data['daily']['time'];
        final List temps = data['daily']['temperature_2m_max'];
        final List codes = data['daily']['weathercode'];
        final List humidity = data['daily']['relative_humidity_2m_max'];
        final List wind = data['daily']['windspeed_10m_max'];
        
        final forecastList = await Future.wait(List.generate(dates.length, (i) async {
        final dayName = getDayNameInNative(dates[i], _langCode);
        final temp = convertToNativeDigits(temps[i].toString(), _langCode);
        final hum = convertToNativeDigits(humidity[i].toString(), _langCode);
        final windSpeed = convertToNativeDigits(wind[i].toString(), _langCode);
        final englishDesc = getWeatherDescFromCode(codes[i]);
        final nativeDesc = await translateToNative(englishDesc);
        final icon = getWeatherIcon(codes[i]);
        final humidityLabel = await translateToNative('Humidity');
        final windLabel = await translateToNative('Wind');
        final tempLabel = await translateToNative('Temperature');

        return "$icon $dayName: $englishDesc ($nativeDesc), "
              "$tempLabel: ${temps[i]}°C, "
              "💧 Humidity ($humidityLabel): ${humidity[i]}%, "
              "🌬️ Wind ($windLabel): ${wind[i]} km/h";

        }));

        setState(() {
          _forecast = forecastList;
          _weatherInfo = forecastList[0]; // Show today’s forecast
        });
      } else {
        setState(() => _weatherInfo = '⚠️ Weather not available');
      }
    } catch (e) {
      print("❌ Error fetching weather: $e");
      setState(() => _weatherInfo = '❌ Error fetching weather');
    }
  } 
  String getWeatherIcon(int code) {
    if (code == 0) return '☀️';
    if (code == 1 || code == 2) return '🌤️';
    if (code == 3) return '☁️';
    if (code >= 45 && code <= 48) return '🌫️';
    if (code >= 51 && code <= 55) return '🌦️';
    if (code >= 61 && code <= 65) return '🌧️';
    if (code >= 71 && code <= 75) return '❄️';
    if (code >= 80 && code <= 82) return '🌧️';
    return '❓';
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
      // ... add more as needed
    };
    return mapping[code] ?? 'Unknown';
  }

  String getDayName(String date) {
    final dateTime = DateTime.parse(date);
    final weekday = dateTime.weekday;
    const weekdays = [
      '', // index 0 placeholder
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return weekdays[weekday];
  }
  Future<String> translateToNative(String text) async {
    final translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _getMLKitLanguage(_langCode),
    );

    final translated = await translator.translateText(text);
    await translator.close();
    return translated;
  }

  String convertToNativeDigits(String number, String langCode) {
    const digitMaps = {
      'kn': ['೦', '೧', '೨', '೩', '೪', '೫', '೬', '೭', '೮', '೯'],
      'hi': ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'],
      'ta': ['௦', '௧', '௨', '௩', '௪', '௫', '௬', '௭', '௮', '௯'],
      'te': ['౦', '౧', '౨', '౩', '౪', '౫', '౬', '౭', '౮', '౯'],
      // Add more as needed
    };

    final digits = digitMaps[langCode] ?? ['0','1','2','3','4','5','6','7','8','9'];

    return number.split('').map((c) {
      final i = int.tryParse(c);
      return (i != null) ? digits[i] : c;
    }).join();
  }

  Map<String, List<String>> weekdayTranslations = {
    'en': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    'kn': ['ಸೋಮವಾರ', 'ಮಂಗಳವಾರ', 'ಬುಧವಾರ', 'ಗುರುವಾರ', 'ಶುಕ್ರವಾರ', 'ಶನಿವಾರ', 'ಭಾನುವಾರ'],
    'hi': ['सोमवार', 'मंगलवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार', 'रविवार'],
    'ta': ['திங்கள்', 'செவ்வாய்', 'புதன்', 'வியாழன்', 'வெள்ளி', 'சனி', 'ஞாயிறு'],
    'te': ['సోమవారం', 'మంగళవారం', 'బుధవారం', 'గురువారం', 'శుక్రవారం', 'శనివారం', 'ఆదివారం'],
    'ml': ['തിങ്കള്‍', 'ചൊവ്വ', 'ബുധന്‍', 'വ്യാഴം', 'വെള്ളി', 'ശനി', 'ഞായര്‍'],
    'bn': ['সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'],
  };

  String getDayNameInNative(String date, String langCode) {
    final dateTime = DateTime.parse(date);
    final weekdayIndex = dateTime.weekday - 1; // 0-based index
    final nativeWeekdays = weekdayTranslations[langCode] ?? weekdayTranslations['en']!;
    return nativeWeekdays[weekdayIndex];
  }

  Future<void> _speakVisibleText() async {
    final buffer = StringBuffer();

    if (_locationMessage != null) buffer.writeln(_locationMessage);
    buffer.writeln(_weatherInfo);
    for (final line in _forecast) buffer.writeln(line);
    buffer.writeln(titleText.split('\n').last); // Only translated   emulator -avd Pixel_7a
    
    final db = await DatabaseHelper().db;
    final logs = await db.query('voice_logs', orderBy: 'id DESC', limit: 5);
    for (final log in logs) {
      buffer.writeln(log['query']);
    }

    await flutterTts.setLanguage(_langCode);
    await flutterTts.speak(buffer.toString());
  }
  
  void _startListening() async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        print("Microphone permission not granted.");
        return; // Exit if permission not granted
      }
    }

    // Only attempt to listen if _speech is available and not already listening
    if (_speechAvailable && !_speech.isListening) {
      setState(() {
        _isListening = true; // Set to true when actively listening starts
        _isPaused = false;   // Ensure not paused when starting
      });
      print("Starting speech recognition...");
      _speech.listen(
        localeId: getSpeechLocale(_langCode),
        listenMode: stt.ListenMode.dictation, // Continuous mode
        onResult: (result) async {
          if (result.recognizedWords.trim().isNotEmpty) {
            final nativeText = result.recognizedWords;
            final englishText = await translateNativeToEnglish(nativeText);
            setState(() {
              _text = "$nativeText\n(English: $englishText)"; // Update main display
              // Append recognized words to the text controller
              if (_textController.text.isEmpty) {
                _textController.text = nativeText;
              } else {
                _textController.text = "${_textController.text} $nativeText";
              }
            });
          }
        },
        onSoundLevelChange: (level) {
          // Optional: Implement a visualizer for sound level if desired
          // print("Sound level: $level");
        },
      );
    } else if (_speech.isListening) {
      print("Already listening, no need to start again.");
    } else if (!_speechAvailable) {
      print("Speech recognition not available.");
    }
  }

  // Refined _stopListening to reset all states correctly
  void _stopListening() async {
    if (_speech.isListening) {
      print("Stopping speech recognition...");
      await _speech.stop();
    }
    setState(() {
      _isListening = false;
      _isLocked = false; // Always unlock when explicitly stopping
      _isPaused = false; // Always unpause when explicitly stopping
      _text = 'Tap the mic to start speaking...'; // Reset prompt
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titleApp)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 135.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            (_locationMessage != null)
                ? Text("📍 $_locationMessage", style: TextStyle(fontSize: 16))
                : Text("📍 $locationFetchingText",
                    style: TextStyle(fontSize: 16, color: Colors.grey)),

            if (_weatherInfo != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text("🌤️ $weatherLabel: $_weatherInfo",
                    style: TextStyle(fontSize: 16)),
              ),

            if (_forecast.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _showFullForecast = !_showFullForecast),
                    child: Text("📅 $forecastLabel (tap to expand):",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (_showFullForecast)
                    ..._forecast.map((f) =>
                        Text(f, style: TextStyle(fontSize: 14))),
                ],
              ),
            SizedBox(height: 20),

            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      titleText,
                      style: TextStyle(fontSize: 24),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 10),
            Text(_text, style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            Text("🧾 $recentLogsLabel:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper().db.then(
                    (db) => db.query('voice_logs',
                        orderBy: 'id DESC', limit: 5),
                  ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return CircularProgressIndicator();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: snapshot.data!.map((log) {
                    return Text("🗒️ ${log['query']}",
                        style: TextStyle(fontSize: 16));
                  }).toList(),
                );
              },
            ),

            SizedBox(height: 40),

            Center(
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => print('Continue pressed'),
                    icon: Icon(Icons.arrow_forward),
                    label: Text(continueText),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 12.0),
                      textStyle: TextStyle(fontSize: 16),
                    ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const CropInfoScreen()),
                      );
                    },
                    icon: Icon(Icons.agriculture),
                    label: Text("ಬೆಳೆ ಮಾಹಿತಿ"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 12.0),
                      textStyle: TextStyle(fontSize: 16),
                      backgroundColor: Colors.amber,
                    ),
                  ),
                  SizedBox(height: 5),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => HolidayListScreen()),
                      );
                    },
                    child: Text("📅 Show Holidays"),
                  ),
                  SizedBox(height: 5),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // get location first
                      Position position = await Geolocator.getCurrentPosition();
                      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
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
                    },
                    icon: Icon(Icons.price_check),
                    label: Text("Market Prices"),
                  ),
                  SizedBox(height: 5),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AddressListScreen()),
                      );
                    },
                    child: Text("📌 Show Address"),
                  ),
                  SizedBox(height: 5),
                  // NEW BUTTON: Navigate to Query Response Screen, passing _langCode
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => QueryResponseScreen(
                          initialLangCode: _langCode, // Pass the language code here
                        )),
                      );
                    },
                    icon: Icon(Icons.chat),
                    label: Text("💬 Chat with Assistant"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 12.0),
                      textStyle: TextStyle(fontSize: 16),
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: Row(
          children: [
            // 📝 Text Box with mic + voice controls
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    // Text box
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Speak...',
                          border: InputBorder.none,
                        ),
                        style: TextStyle(fontSize: 14),
                        maxLines: 3,
                      ),
                    ),

                    // Mic button column
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isListening && !_isLocked) // Only show slide up hint when actively listening and not locked
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text(
                              '',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        if (_isLocked) // Show "Locked" text when mic is locked
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text(
                              '🔒 Locked',
                              style: TextStyle(fontSize: 12, color: Colors.blue),
                            ),
                          ),
                        GestureDetector(
                          onTapDown: (details) {
                            _initialY = details.localPosition.dy; // Reset initial Y
                            if (!_isListening && !_isLocked) { // Start listening only if not already active or locked
                              _startListening();
                            } else if (_isPaused) { // If paused and tapped down, resume
                               print("Resuming listening from tap down (previously paused).");
                              _startListening();
                            }
                          },
                          onTapUp: (details) {
                            // If it was a quick tap and not locked, stop listening
                            if (!_isLocked && _isListening) { // Ensure it was listening before stopping
                              _stopListening();
                            }
                            // If it was locked, keep listening, tapUp doesn't stop it
                          },
                          onLongPress: () {
                            if (!_isLocked) { // Only lock if not already locked
                              setState(() => _isLocked = true);
                              print("Mic locked via long press.");
                              _startListening(); // Ensure continuous listening
                            }
                          },
                          onPanUpdate: (details) {
                            final dy = details.localPosition.dy - _initialY;
                            if (dy < -30 && !_isLocked) { // Moved up more than 30 pixels and not already locked
                              setState(() => _isLocked = true);
                              print("Mic locked via slide up gesture.");
                              _startListening(); // Ensure continuous listening
                            }
                          },
                          onPanEnd: (_) {
                            // If not locked, stop listening when finger is lifted
                            if (!_isLocked && _isListening) { // Ensure it was listening before stopping
                              _stopListening();
                            }
                            // If locked, do nothing on pan end, as it's continuous
                          },
                          child: Icon(
                            // Mic icon is ON if either listening OR locked
                            _isListening || _isLocked ? Icons.mic : Icons.mic_none,
                            // Color is red if either listening OR locked
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

            SizedBox(width: 5),

            // Optional controls (only if recording or locked AND there's text)
            if ((_isListening || _isLocked) && _textController.text.isNotEmpty) ...[
              FloatingActionButton(
                heroTag: 'send',
                mini: true,
                backgroundColor: Colors.green,
                onPressed: () async {
                  final text = _textController.text.trim();
                  if (text.isNotEmpty) {
                    final englishText = await translateNativeToEnglish(text);
                    await DatabaseHelper().insertVoiceLog(englishText);
                  }
                  // After sending, stop listening and reset all states
                  _stopListening();
                  setState(() {
                    _textController.clear();
                    _text = 'Tap the mic to start speaking...'; // Reset main text display
                  });
                },
                child: Icon(Icons.send, size: 18),
              ),
              SizedBox(width: 5),

              FloatingActionButton(
                heroTag: 'cancel',
                mini: true,
                onPressed: () {
                  // On delete, clear text and stop listening, resetting all states
                  _stopListening();
                  setState(() {
                    _textController.clear();
                    _text = 'Tap the mic to start speaking...'; // Reset main text display
                  });
                },
                child: Icon(Icons.delete, size: 18),
              ),
              SizedBox(width: 5),

              FloatingActionButton(
                heroTag: 'play_pause_resume',
                mini: true,
                backgroundColor: Colors.blueAccent,
                onPressed: () async {
                  if (_isPaused) {
                    // If currently paused, resume listening
                    print("Resuming listening...");
                    _startListening(); // This will also set _isPaused = false internally
                  } else {
                    // If currently listening (or not paused), clicking this means we want to PAUSE.
                    print("Pausing listening...");
                    await _speech.stop(); // Stop the speech recognizer
                    setState(() {
                      _isListening = false; // No longer actively listening (from speech_to_text's perspective)
                      _isPaused = true;     // Set to paused state
                      // _isLocked should remain true if it was locked, as pausing doesn't unlock.
                    });
                  }
                },
                child: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 18),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
