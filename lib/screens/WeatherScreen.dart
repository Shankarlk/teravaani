import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;
import 'package:teravaani/database/database_helper.dart';
import 'package:teravaani/main.dart';
import '../api/pageapi.dart';

class WeatherScreen extends StatefulWidget {
  final List<String> forecastDisplay;
  final List<String> forecastSpeak;
  final List<int> forecastCodes;
  final String targetLangCode;

  const WeatherScreen({
    super.key,
    required this.forecastDisplay,
    required this.forecastSpeak,
    required this.forecastCodes,
    required this.targetLangCode,
  });

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with WidgetsBindingObserver {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  List<String> _forecastDisplay = [];
  List<String> _forecastSpeak = [];
  List<int> _forecastCodes = [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();
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
    _flutterTts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
    _flutterTts.setCancelHandler(() {
      setState(() => _isSpeaking = false);
    });
    PageAPI.logPageVisit("WeatherScreen");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.forecastDisplay.isEmpty) {
        setState(() => _isSpeaking = false);
        _fetchForecast(); // ✅ Fetch if empty
      } else {
        setState(() {
          _forecastDisplay = widget.forecastDisplay;
          _forecastSpeak = widget.forecastSpeak;
          _forecastCodes = widget.forecastCodes;
          _loading = false;
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_forecastSpeak.isNotEmpty) {
            _toggleSpeech();
          }
        });
      }
    });
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
      await _flutterTts.speak(msg); // 🔊 Speak the message
    }
  }

  Future<void> _fetchForecast() async {
    final savedSettings = await DatabaseHelper().getUserSettings();
    if (savedSettings != null) {
      print("📦 Loaded location from DB");
      final state = savedSettings['state'];
      final district = savedSettings['district'];
      final lang = savedSettings['language'];
      PageAPI.setLocation(district: district, state: state);
      // PageAPI.logPageVisit("HomeScreen");

      try {
        final locations = await locationFromAddress("$district, $state");
        if (locations.isNotEmpty) {
          final lat = locations.first.latitude;
          final lon = locations.first.longitude;

          try {
            final url = Uri.parse(
              'https://api.weatherapi.com/v1/forecast.json'
              '?key=1046d3b300794f6b90e122255252909'
              '&q=$lat,$lon'
              '&days=7'
              '&aqi=no&alerts=no',
            );

            final response = await http.get(url);
            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final forecastDays = data['forecast']['forecastday'] as List;

              // Extract values
              final List dates = forecastDays.map((e) => e['date']).toList();
              final List<double> temps = forecastDays
                  .map((e) => (e['day']['maxtemp_c'] as num).toDouble())
                  .toList();
              final List<double> humidity = forecastDays
                  .map((e) => (e['day']['avghumidity'] as num).toDouble())
                  .toList();
              final List<double> wind = forecastDays
                  .map((e) => (e['day']['maxwind_kph'] as num).toDouble())
                  .toList();
              final List<int> codes = forecastDays
                  .map((e) => (e['day']['condition']['code'] as num).toInt())
                  .toList();
              final List<String> conditions = forecastDays
                  .map((e) => e['day']['condition']['text'].toString())
                  .toList();

              // --- TODAY’s summary (for header) ---
              final condition = conditions[0];
              final nativeCondition = await translateToNative(condition);

              // --- FULL Forecast (with day name included) ---
              final forecastList = await Future.wait(
                List.generate(dates.length, (i) async {
                  final dayName = getDayNameInNative(
                    dates[i],
                    widget.targetLangCode,
                  );
                  final nativeDayName =
                      RegExp(r'\((.*?)\)').firstMatch(dayName)?.group(1) ?? '';

                  final nativeDesc = await translateToNative(conditions[i]);
                  final englishDesc = conditions[i];

                  final tempVal = temps[i].toStringAsFixed(1);
                  final humVal = humidity[i].toStringAsFixed(0);
                  final windVal = wind[i].toStringAsFixed(0);

                  final temp = convertToNativeDigits(
                    tempVal,
                    widget.targetLangCode,
                  );
                  final hum = convertToNativeDigits(
                    humVal,
                    widget.targetLangCode,
                  );
                  final winds = convertToNativeDigits(
                    windVal,
                    widget.targetLangCode,
                  );

                  final tempLabel = await translateToNative('Temperature');
                  final humLabel = await translateToNative('Humidity');
                  final windLabel = await translateToNative('Wind');

                  return {
                    "display":
                        "$dayName: $englishDesc ($nativeDesc), "
                        "$tempLabel: $tempVal°C, "
                        "💧 Humidity ($humLabel): $humVal%, "
                        "🌬️ Wind ($windLabel): $windVal km/h",
                    "speak":
                        "$nativeDayName: $nativeDesc, "
                        "$tempLabel: $temp ಡಿಗ್ರಿ ಸೆಲ್ಸಿಯಸ್, "
                        "$humLabel: $hum ಶೇಕಡಾ, "
                        "$windLabel: $winds ಕಿ.ಮೀ/ಗಂ",
                  };
                }),
              );

              setState(() {
                _forecastDisplay = forecastList
                    .map((e) => e['display'] as String)
                    .toList();
                _forecastSpeak = forecastList
                    .map((e) => e['speak'] as String)
                    .toList();
                _forecastCodes = codes;
                _loading = false;
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_forecastSpeak.isNotEmpty) {
                  _toggleSpeech();
                }
              });
            } else {
              setState(() => _loading = false);
            }
          } catch (e) {
            print("❌ Exception fetching weather: $e");
            setState(() => _loading = false);
          }
        } else {
          print("⚠️ Could not resolve location from address");
          setState(() => _loading = false);
        }
      } catch (e) {
        print("❌ Geocoding failed: $e");
        setState(() => _loading = false);
      }
      return;
    }
  }

  String convertToNativeDigits(String number, String langCode) {
    const digitMaps = {
      'kn': ['೦', '೧', '೨', '೩', '೪', '೫', '೬', '೭', '೮', '೯'],
      'hi': ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'],
      'ta': ['௦', '௧', '௨', '௩', '௪', '௫', '௬', '௭', '௮', '௯'],
      'te': ['౦', '౧', '౨', '౩', '౪', '౫', '౬', '౭', '౮', '౯'],
      // Add more as needed
    };

    final digits =
        digitMaps[langCode] ??
        ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    return number.split('').map((c) {
      final i = int.tryParse(c);
      return (i != null) ? digits[i] : c;
    }).join();
  }

  String getDayNameInNative(String date, String langCode) {
    final dateTime = DateTime.parse(date);
    final weekdayIndex = dateTime.weekday - 1; // 0-based index

    const englishWeekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final nativeWeekdays =
        weekdayTranslations[langCode] ?? weekdayTranslations['en']!;
    final native = nativeWeekdays[weekdayIndex];
    final english = englishWeekdays[weekdayIndex];

    return '$english ($native)';
  }

  Map<String, List<String>> weekdayTranslations = {
    'en': [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ],
    'kn': [
      'ಸೋಮವಾರ',
      'ಮಂಗಳವಾರ',
      'ಬುಧವಾರ',
      'ಗುರುವಾರ',
      'ಶುಕ್ರವಾರ',
      'ಶನಿವಾರ',
      'ಭಾನುವಾರ',
    ],
    'hi': [
      'सोमवार',
      'मंगलवार',
      'बुधवार',
      'गुरुवार',
      'शुक्रवार',
      'शनिवार',
      'रविवार',
    ],
    'ta': [
      'திங்கள்',
      'செவ்வாய்',
      'புதன்',
      'வியாழன்',
      'வெள்ளி',
      'சனி',
      'ஞாயிறு',
    ],
    'te': [
      'సోమవారం',
      'మంగళవారం',
      'బుధవారం',
      'గురువారం',
      'శుక్రవారం',
      'శనివారం',
      'ఆదివారం',
    ],
    'ml': ['തിങ്കള്‍', 'ചൊവ്വ', 'ബുധന്‍', 'വ്യാഴം', 'വെള്ളി', 'ശനി', 'ഞായര്‍'],
    'bn': [
      'সোমবার',
      'মঙ্গলবার',
      'বুধবার',
      'বৃহস্পতিবার',
      'শুক্রবার',
      'শনিবার',
      'রবিবার',
    ],
  };

  Future<void> _toggleSpeech() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
    } else {
      final visibleIndices = _getVisibleIndices();
      final texts = visibleIndices.map((i) => _forecastSpeak[i]).toList();
      final nativeText = texts.join('. ');

      if (nativeText.trim().isNotEmpty) {
        setState(() => _isSpeaking = true);
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.setPitch(1.0);
        await _flutterTts.speak(nativeText);
      }
    }
  }

  List<int> _getVisibleIndices() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !_scrollController.hasClients) return [];

    final viewport = _scrollController.position;
    final firstPixel = viewport.pixels;
    final lastPixel = viewport.pixels + viewport.viewportDimension;

    List<int> visible = [];
    double itemHeight =
        180; // approximate card height (tweak as per your design)

    for (int i = 0; i < _forecastSpeak.length; i++) {
      final itemTop = i * itemHeight;
      final itemBottom = itemTop + itemHeight;
      if (itemBottom >= firstPixel && itemTop <= lastPixel) {
        visible.add(i);
      }
    }
    return visible;
  }

  IconData getWeatherIcon(int code) {
    switch (code) {
      case 1000:
        return Icons.wb_sunny; // Sunny
      case 1003:
        return Icons.wb_cloudy; // Partly Cloudy
      case 1006:
        return Icons.cloud; // Cloudy
      case 1009:
        return Icons.cloud; // Overcast
      case 1030:
        return FontAwesomeIcons.smog; // Mist
      case 1063:
        return FontAwesomeIcons.cloudSunRain; // Patchy Rain
      case 1066:
        return FontAwesomeIcons.snowflake; // Snow Showers
      case 1069:
        return FontAwesomeIcons.snowflake; // Snow Showers
      case 1072:
        return FontAwesomeIcons.snowflake; // Freezing Drizzle
      case 1087:
        return FontAwesomeIcons.cloudBolt; // Thunderstorms
      case 1114:
        return FontAwesomeIcons.snowflake; // Snow Showers
      case 1117:
        return FontAwesomeIcons.snowflake; // Snow Showers
      case 1135:
        return FontAwesomeIcons.smog; // Mist
      case 1147:
        return FontAwesomeIcons.smog; // Fog
      case 1150:
        return FontAwesomeIcons.cloudRain; // Light Drizzle
      case 1153:
        return FontAwesomeIcons.cloudRain; // Light Drizzle
      case 1168:
        return FontAwesomeIcons.cloudRain; // Light Drizzle
      case 1171:
        return FontAwesomeIcons.cloudRain; // Light Drizzle
      case 1180:
        return FontAwesomeIcons.cloudRain; // Light Rain
      case 1183:
        return FontAwesomeIcons.cloudRain; // Light Rain
      case 1186:
        return FontAwesomeIcons.cloudRain; // Light Rain
      case 1189:
        return FontAwesomeIcons.cloudRain; // Light Rain
      case 1192:
        return FontAwesomeIcons.cloudRain; // Moderate Rain
      case 1195:
        return FontAwesomeIcons.cloudRain; // Moderate Rain
      case 1198:
        return FontAwesomeIcons.cloudRain; // Moderate Rain
      case 1201:
        return FontAwesomeIcons.cloudRain; // Heavy Rain
      case 1204:
        return FontAwesomeIcons.cloudRain; // Heavy Rain
      case 1207:
        return FontAwesomeIcons.cloudRain; // Freezing Rain
      case 1210:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1213:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1216:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1219:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1222:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1225:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1237:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1240:
        return FontAwesomeIcons.cloudRain; // Light Rain
      case 1243:
        return FontAwesomeIcons.cloudRain; // Light Rain
      case 1246:
        return FontAwesomeIcons.cloudRain; // Light Rain
      case 1249:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1252:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1255:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1258:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1261:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1264:
        return FontAwesomeIcons.snowflake; // Light Snow
      case 1273:
        return FontAwesomeIcons.cloudBolt; // Thunderstorms
      case 1276:
        return FontAwesomeIcons.cloudBolt; // Thunderstorms
      case 1279:
        return FontAwesomeIcons.cloudBolt; // Thunderstorms
      case 1282:
        return FontAwesomeIcons.cloudBolt; // Thunderstorms
      default:
        return Icons.help_outline; // Default icon for unknown codes
    }
    // if (code == 0) return Icons.wb_sunny;
    // if (code == 1 || code == 2) return Icons.wb_cloudy;
    // if (code == 3) return Icons.cloud;
    // if (code >= 45 && code <= 48) return FontAwesomeIcons.smog; // 🌫️ Fog
    // if (code >= 51 && code <= 55)
    //   return FontAwesomeIcons.cloudSunRain; // 🌦️ Light rain showers
    // if (code >= 61 && code <= 65) return FontAwesomeIcons.cloudRain; // 🌧️ Rain
    // if (code >= 71 && code <= 75) return FontAwesomeIcons.snowflake; // ❄️ Snow
    // if (code >= 80 && code <= 82)
    //   return FontAwesomeIcons.cloudShowersHeavy; // 🌧️ Heavy rain
    // if (code == 95 || code == 96 || code == 99)
    //   return FontAwesomeIcons.cloudBolt;
    // return Icons.help_outline;
  }

  Future<String> translateToNative(String text) async {
    try {
      final t = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(widget.targetLangCode),
      );
      final translated = await t.translateText(text);
      await t.close();
      return translated;
    } catch (_) {
      return text;
    }
  }

  TranslateLanguage _getMLKitLanguage(String code) {
    switch (code) {
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

  Color getWeatherColor(int code) {
    switch (code) {
      // Sunny
      case 1000:
        return Colors.orange;

      // Partly Cloudy
      case 1003:
        return Colors.grey.shade400;

      // Cloudy / Overcast
      case 1006:
      case 1009:
        return Colors.grey.shade500;

      // Mist / Fog / Haze
      case 1030:
      case 1135:
      case 1147:
        return Colors.brown;

      // Patchy Rain / Light Drizzle / Light Rain
      case 1063:
      case 1150:
      case 1153:
      case 1168:
      case 1171:
      case 1180:
      case 1183:
        return Colors.lightBlue;

      // Moderate Rain
      case 1186:
      case 1189:
      case 1192:
      case 1195:
        return Colors.blue;

      // Heavy Rain / Freezing Rain
      case 1201:
      case 1204:
      case 1207:
      case 1240:
      case 1243:
      case 1246:
        return const Color.fromARGB(255, 28, 38, 99);

      // Snow / Sleet / Light Snow
      case 1066:
      case 1069:
      case 1072:
      case 1114:
      case 1117:
      case 1210:
      case 1213:
      case 1216:
      case 1219:
      case 1222:
      case 1225:
      case 1237:
      case 1249:
      case 1252:
      case 1255:
      case 1258:
      case 1261:
      case 1264:
        return const Color.fromARGB(255, 118, 176, 184);

      // Thunderstorms
      case 1087:
      case 1273:
      case 1276:
      case 1279:
      case 1282:
        return Colors.deepPurple;

      // Default / unknown
      default:
        return Colors.black;
    }
    // if (code == 0) return Colors.orange; // ☀️ Sunny
    // if (code == 1 || code == 2 || code == 3) return const Color.fromARGB(255, 212, 204, 204); // ☁️ Cloudy
    // if (code >= 45 && code <= 48) return Colors.brown; // 🌫️ Fog
    // if (code >= 51 && code <= 55) return Colors.lightBlue; // 🌦️ Light rain
    // if (code >= 61 && code <= 65) return Colors.blue; // 🌧️ Rain
    // if (code >= 71 && code <= 75) return const Color.fromARGB(255, 118, 176, 184); // ❄️ Snow
    // if (code >= 80 && code <= 82) return const Color.fromARGB(255, 28, 38, 99); // 🌧️ Heavy rain
    // if (code == 95 || code == 96 || code == 99) return Colors.deepPurple; // ⛈️ Thunderstorm
    // return Colors.black; // default / unknown
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flutterTts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is minimized / backgrounded
      if (_isSpeaking) {
        _flutterTts.stop();
        setState(() => _isSpeaking = false);
      }
    }
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
        backgroundColor: Colors.white, // black background like screenshot
        appBar: AppBar(
          title: FutureBuilder<String>(
            future: translateToNative(
              "Weather Forecast",
            ), // translate the title
            builder: (context, snapshot) {
              final translated = snapshot.data ?? "";
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 📝 Title (English + Native)
                  Expanded(
                    child: Text(
                      "Weather Forecast\n($translated)",
                      style: const TextStyle(
                        color: Colors.white, // white text color
                        fontWeight: FontWeight.w700, // bold
                        fontSize: 18,
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
              );
            },
          ),
          backgroundColor: Colors.green.shade700,
          iconTheme: const IconThemeData(
            color: Colors.white, // back button color
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _forecastDisplay.isEmpty
              ? const Center(child: Text('No forecast available'))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _forecastDisplay.length,
                  itemBuilder: (context, index) {
                    final forecastText = _forecastDisplay[index];
                    final weatherCode = _forecastCodes[index];

                    // Split day and details
                    final parts = forecastText.split(":");
                    final dayPart = parts.isNotEmpty ? parts[0].trim() : "Day";
                    final detailsPart = parts.length > 1
                        ? parts.sublist(1).join(":").trim()
                        : "";

                    // Extract temperature
                    final tempMatch = RegExp(
                      r'([-+]?\d+(\.\d+)?)',
                    ).firstMatch(detailsPart);
                    final temperature = tempMatch != null
                        ? "${tempMatch.group(0)}°C"
                        : "--°C";

                    // Extract condition (text before first comma)
                    final conditionPart = detailsPart.split(",").isNotEmpty
                        ? detailsPart.split(",")[0].trim()
                        : "";

                    // Extract humidity and wind values
                    final humMatch = RegExp(
                      r'Humidity.*?(\d+)%',
                    ).firstMatch(detailsPart);
                    final windMatch = RegExp(
                      r'Wind.*?(\d+)\s?km/h',
                    ).firstMatch(detailsPart);
                    final humidityVal = humMatch != null
                        ? humMatch.group(1)!
                        : "--";
                    final windVal = windMatch != null
                        ? windMatch.group(1)!
                        : "--";

                    return FutureBuilder(
                      future: Future.wait([
                        translateToNative('Humidity'),
                        translateToNative('Wind'),
                      ]),
                      builder: (context, snapshot) {
                        final labels = snapshot.data ?? ['Humidity', 'Wind'];
                        final humidityNative = labels[0];
                        final windNative = labels[1];

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Day
                                Text(
                                  dayPart,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Row: Thermometer + Temp + Condition + Weather Icon
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // const Icon(Icons.thermostat, size: 60, color: Colors.black),
                                    Icon(
                                      getWeatherIcon(weatherCode),
                                      size: 50,
                                      color: getWeatherColor(weatherCode),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          temperature,
                                          style: const TextStyle(
                                            fontSize: 23,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 100,
                                          child: Text(
                                            conditionPart,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    // const SizedBox(width: 20),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // Row: Humidity & Wind (both English + native labels)
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.opacity,
                                          size: 20,
                                          color: Colors.blue,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Humidity ($humidityNative): $humidityVal%", // both labels
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color.fromARGB(251, 7, 6, 6),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.air,
                                          size: 20,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Wind ($windNative): $windVal km/h", // both labels
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color.fromARGB(251, 7, 6, 6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _toggleSpeech,
          backgroundColor: _isSpeaking ? Colors.grey : Colors.blue,
          tooltip: _isSpeaking ? "Pause" : "Speak forecast",
          child: Icon(
            _isSpeaking ? Icons.pause : Icons.volume_up,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
