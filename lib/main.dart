import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:teravaani/screens/SplashScreen.dart';
import './database/database_helper.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import './screens/market_price_screen.dart';
import './screens/query_response_screen.dart';
import './screens/WeatherScreen.dart';
import './screens/CropManagementScreen.dart';
import 'route_observer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import './api/pageapi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:ui';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().db;
  //await preDownloadAllMLKitModels();

  runApp(
    MaterialApp(
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
    ),
  );
}

class VoiceHomePage extends StatefulWidget {
  @override
  _VoiceHomePageState createState() => _VoiceHomePageState();
}

class _VoiceHomePageState extends State<VoiceHomePage>
    with WidgetsBindingObserver, RouteAware {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  List<String> _forecast = [];
  List<String> _forecastSpeak = [];
  final FlutterTts flutterTts = FlutterTts();
  String _langCode = 'en';
  String titleText = 'Speak Now';
  String continueText = 'Continue';
  String titleApp = 'Teravaani';
  String locationFetchingText = 'Fetching location...';
  String weatherLabel = 'Weather';
  String forecastLabel = '7-Day Forecast';
  String recentLogsLabel = 'Recent Voice Logs';
  final TextEditingController _textController = TextEditingController();
  bool _speechAvailable = false;
  bool _isLocked = false;
  bool _isPaused = false;
  String userId = " ";
  double _currentTemperature = 0.0;
  String _currentCondition = 'Loading...';
  String _nativeCondition = '';
  String _todayWeatherTitleNative = '';
  String lblcroptitleNative = '';
  String lblmarkettitleNative = '';
  int _currentWeatherCode = 0;
  List<int> forecodes = List.empty();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _hasInternet = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  WidgetsBinding.instance.addObserver(this);
    _requestPermissions().then((_) async {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          print(
            "Speech status: $status (isListening: $_isListening, isLocked: $_isLocked, isPaused: $_isPaused)",
          );
          if (status == 'notListening') {
            if (_isLocked && !_isPaused) {
              print(
                "Attempting auto-restart due to notListening (locked mic).",
              );
              Future.delayed(Duration(milliseconds: 500), () {
                if (!_speech.isListening && !_isPaused && _isLocked) {
                  print("Auto-restarting listening (condition met).");
                  _startListening();
                } else {
                  print(
                    "Auto-restart condition not met (isListening: ${_speech.isListening}, isPaused: $_isPaused, isLocked: $_isLocked).",
                  );
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
    _initializeLocalNotifications();
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
    _checkAndShowReminders();
    flutterTts.setSpeechRate(0.5); // optional
    flutterTts.setPitch(1.0);
    getOrCreateDeviceId();
    _initializeLocationAndStates();
  }

  Future<void> _initializeLocationAndStates() async {
    //_statesList =await fetchStates();        // fetch states first
    await _getLocation(); // try getting location
    _speakContent();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is minimized / backgrounded
        _flutterTts.stop();
        setState(() => _isSpeaking = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _flutterTts.stop();
    super.dispose();
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

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidInit,
    );

    await flutterLocalNotificationsPlugin.initialize(settings);
  }

  Future<void> _checkAndShowReminders() async {
    final userIds = await getOrCreateDeviceIdNoti();
    final events = await fetchUpcomingEvents(userIds);
    final today = DateTime.now();

    for (final event in events) {
      final eventDate = DateTime.parse(event['ScheduledDate']);
      final diff = eventDate.difference(today).inDays;

      if (diff == 2 || diff == 1 || diff == 0) {
        final formattedDate = DateFormat('d MMMM yyyy').format(eventDate);

        // Translate labels and values
        final eventLabelNative = await translateToNative("Event");
        final dateLabelNative = await translateToNative("Date");
        final eventTypeNative = await translateToNative(event['EventType']);
        final formattedDateNt = await translateToNative(formattedDate);

        final alertTitleNative = await translateToNative("Upcoming Event");
        final okTextNative = await translateToNative("OK");

        final messageNative =
            "$eventTypeNative\n $dateLabelNative: $formattedDateNt)";

        // 🔊 Speak in native language
        //await flutterTts.speak(messageNative);

        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              'event_channel_id',
              'Event Reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            );
        print("shotification");

        const NotificationDetails notificationDetails = NotificationDetails(
          android: androidDetails,
        );
        final int notificationId =
            (event['ID'] ??
                DateTime.now().second * 1000 + DateTime.now().millisecond) %
            100000;
        await flutterLocalNotificationsPlugin.show(
          notificationId, // Unique ID for the notification
          alertTitleNative, // Title
          messageNative, // Body
          notificationDetails,
        );
        await markReminderSent(event['ID']);
        break;
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchUpcomingEvents(String userIds) async {
    final url = Uri.parse(
      "https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/api/upcoming-events/$userIds",
    );

    final response = await http.get(url);
    print("response ${response.body}");
    print("response statusCode ${response.statusCode}");

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);

      if (data['success'] == true && data['events'] is List) {
        return List<Map<String, dynamic>>.from(data['events']);
      } else {
        throw Exception("API format unexpected");
      }
    } else {
      throw Exception("Failed to fetch upcoming events");
    }
  }

  Future<void> markReminderSent(int calendarId) async {
    final url = Uri.parse(
      "https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/api/mark-reminder-sent",
    );

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({"calendarId": calendarId}),
    );

    if (response.statusCode != 200) {
      print("⚠️ Failed to mark reminder sent for ID $calendarId");
    }
  }

  Future<String> getOrCreateDeviceIdNoti() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      deviceId = const Uuid().v4(); // Generate UUID
      await prefs.setString('device_id', deviceId);
    }

    return deviceId;
  }

  Future<void> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _showLocationServiceDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        await _showPermissionDeniedDialog();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await _showPermissionDeniedDialog(permanentlyDenied: true);
      return;
    }

    // If permission granted and service enabled, proceed to fetch location
    //_getCurrentLocation(); // Or any logic to proceed
    _getLocation();
  }

  Future<void> _showLocationServiceDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Location Required'),
        content: Text(
          'Please enable location services to continue using the app.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Geolocator.openLocationSettings();
              Navigator.of(context).pop();
              await _requestPermissions(); // Retry after returning
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionDeniedDialog({
    bool permanentlyDenied = false,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Permission Required'),
        content: Text(
          permanentlyDenied
              ? 'Location permission is permanently denied. Please enable it from app settings.'
              : 'Location permission is required to continue using the app.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (permanentlyDenied) {
                await openAppSettings();
              } else {
                await _requestPermissions(); // Retry
              }
              Navigator.of(context).pop();
            },
            child: Text(permanentlyDenied ? 'App Settings' : 'Retry'),
          ),
        ],
      ),
    );
  }

  Map<String, String> appNameNative = {
    'hi': 'तेरवाणी', // Hindi
    'mr': 'तेरवाणी', // Marathi
    'gu': 'તેરવાની', // Gujarati
    'pa': 'ਤੇਰਵਾਣੀ', // Punjabi
    'bn': 'তেরাভানী', // Bengali
    'ta': 'தெரவாணி', // Tamil
    'te': 'తెరవాణి', // Telugu
    'kn': 'ತೆರವಾಣಿ', // Kannada
    'ml': 'തെరవാണി', // Malayalam
    'or': 'ତେରଭାଣି', // Odia
    'as': 'টেৰাভানি', // Assamese
    'ur': 'تیراوانی', // Urdu
    'sd': 'تيراواڻي', // Sindhi
    'ne': 'तेरवानी', // Nepali
    'kok': 'तेरवाणी', // Konkani
    'mai': 'तेरवाणी', // Maithili
    'sa': 'तेरवाणी', // Sanskrit
    'bh': 'तेरवाणी', // Bhojpuri
    'ks': 'تیراوانی', // Kashmiri
  };

  Future<void> _translateUILabels() async {
    String nativeAppName = appNameNative[_langCode] ?? 'Teravaani';
    titleApp = 'Teravaani\n($nativeAppName)';
    locationFetchingText =
        'Fetching location...\n(${await translateToNative('Fetching location...')})';
    weatherLabel = 'Weather\n(${await translateToNative('Weather')})';
    forecastLabel =
        '7-Day Forecast\n(${await translateToNative('7-Day Forecast')})';
    recentLogsLabel =
        'Recent Voice Logs\n(${await translateToNative('Recent Voice Logs')})';
    _todayWeatherTitleNative = await translateToNative('Todays Weather');
    lblcroptitleNative = await translateToNative('Crop Management');
    lblmarkettitleNative = await translateToNative('Market Rates');
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
        _langCode = lang;
      });
      PageAPI.setLocation(district: district, state: state);
      PageAPI.logPageVisit("HomeScreen");

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
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final state = placemark.administrativeArea ?? '';
          final district =
              placemark.subAdministrativeArea ?? placemark.locality ?? '';
          final langCode = getLanguageCodeFromState(state);

          await DatabaseHelper().insertOrUpdateUserSettings(
            language: langCode,
            state: state,
            district: district,
          );

          setState(() {
            _langCode = langCode;
          });
          PageAPI.setLocation(district: district, state: state);
          PageAPI.logPageVisit("HomeScreen");

          await _getWeather(position.latitude, position.longitude);
          await _translateStaticLabels(langCode);
          await _translateUILabels();
        }
      }
    } catch (e) {
      print("❌ Error fetching location: $e");
    }
  }

  Future<List<String>> fetchStates() async {
    final response = await http.get(
      Uri.parse(
        'https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/api/states',
      ),
    );
    if (response.statusCode == 200) {
      return List<String>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load states');
    }
  }

  Future<void> fetchDistricts(String state) async {
    final response = await http.get(
      Uri.parse(
        'https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/api/districts/$state',
      ),
    );
    if (response.statusCode == 200) {
      print("district");
      setState(() {
        //_districtsList = List<String>.from(jsonDecode(response.body));
      });
    } else {
      throw Exception('Failed to load districts');
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
      final isModelDownloaded = await modelManager.isModelDownloaded(
        targetLang.bcpCode,
      );
      print("🟡 Model download started for ${targetLang.bcpCode}");

      if (!isModelDownloaded) {
        await modelManager.downloadModel(
          targetLang.bcpCode,
          isWifiRequired: false,
        );
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

  Future<void> _translateStaticLabels(String langCode) async {
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

  void getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      deviceId = const Uuid().v4(); // Generate UUID
      await prefs.setString('device_id', deviceId);
    }

    userId = deviceId;
  }

  Future<void> _getWeather(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://api.weatherapi.com/v1/forecast.json'
        '?key=1046d3b300794f6b90e122255252909'
        '&q=$lat,$lon'
        '&days=1' // ✅ Only today's weather
        '&aqi=no&alerts=no',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final today = data['forecast']['forecastday'][0];

        final double temp = (today['day']['maxtemp_c'] as num).toDouble();
        final int code = (today['day']['condition']['code'] as num).toInt();
        final String condition = today['day']['condition']['text'].toString();

        final String nativeCondition = await translateToNative(condition);

        setState(() {
          _currentTemperature = temp;
          _currentCondition = condition;
          _nativeCondition = nativeCondition;
          _currentWeatherCode = code;
        });
      } else {
        setState(() {
          _currentCondition = 'Weather unavailable';
          _nativeCondition = '';
        });
      }
    } catch (e) {
      print("❌ Error fetching weather: $e");
      setState(() => _currentCondition = 'Error fetching weather');
    }
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
      95: 'Thunderstorm',
      96: 'Thunderstorm with slight hail',
      99: 'Thunderstorm with heavy hail',
    };
    return mapping[code] ?? 'Unknown';
  }

  String getDayName(String date) {
    final dateTime = DateTime.parse(date);
    final weekday = dateTime.weekday;
    const weekdays = [
      '', // index 0 placeholder
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
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

    final digits =
        digitMaps[langCode] ??
        ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    return number.split('').map((c) {
      final i = int.tryParse(c);
      return (i != null) ? digits[i] : c;
    }).join();
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
        _isPaused = false; // Ensure not paused when starting
      });
      print("Starting speech recognition...");
      _speech.listen(
        localeId: getSpeechLocale(_langCode),
        listenMode: stt.ListenMode.dictation, // Continuous mode
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
        onSoundLevelChange: (level) {},
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
    });
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

  // 1️⃣ Add these variables in your State class
  bool _isSpeaking = false;
  final FlutterTts _flutterTts = FlutterTts();

  // Method to speak the screen content
  Future<void> _speakContent() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
    } else {
      String content =
          """
      $_todayWeatherTitleNative
      $_currentTemperature°C
      $_nativeCondition
      $lblcroptitleNative
      $lblmarkettitleNative
    """;

      setState(() => _isSpeaking = true);

      await _flutterTts.awaitSpeakCompletion(true);

      // Start speaking
      await _flutterTts.speak(content);

      // After finishing, reset the icon
      setState(() => _isSpeaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {

    bool isLoading =
        _todayWeatherTitleNative.isEmpty ||
        _currentTemperature == 0.0 ||
        lblcroptitleNative.isEmpty ||
        lblmarkettitleNative.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              "assets/croplogo.png", // your image path
              height: 50,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 5),
            const Text(
              "Teravaani",
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),

      body: Stack(
        children: [
          // ✅ Main content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🌤️ Weather Card
                GestureDetector(
                  onTap: () {
                    _flutterTts.stop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WeatherScreen(
                          forecastDisplay: _forecast,
                          forecastSpeak: _forecastSpeak,
                          forecastCodes: forecodes,
                          targetLangCode: _langCode,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 253, 253, 251),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          "Today's Weather\n($_todayWeatherTitleNative)",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              getWeatherIcon(_currentWeatherCode),
                              size: 60,
                              color: getWeatherColor(_currentWeatherCode),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  "$_currentTemperature°C",
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
                                    "$_currentCondition\n($_nativeCondition)",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 🌱 Crop Management Card
                GestureDetector(
                  onTap: () {
                    _flutterTts.stop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CropManagementScreen(langCode: _langCode),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade300,
                          blurRadius: 4,
                          offset: const Offset(2, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            FontAwesomeIcons.leaf,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Crop Management\n($lblcroptitleNative)",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 📈 Market Rates Card
                GestureDetector(
                  onTap: () async {
                    Position position = await Geolocator.getCurrentPosition();
                    List<Placemark> placemarks = await placemarkFromCoordinates(
                      position.latitude,
                      position.longitude,
                    );
                    final place = placemarks.first;
                    final district = place.subAdministrativeArea ?? '';
                    final state = place.administrativeArea ?? '';
                    _flutterTts.stop();
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
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade300,
                          blurRadius: 4,
                          offset: const Offset(2, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            FontAwesomeIcons.chartLine,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Market Rates\n($lblmarkettitleNative)",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ✅ Floating Mic + Speaker buttons inside the Stack
          Positioned(
            bottom: 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: "speaker",
                  onPressed: _speakContent,
                  backgroundColor: _isSpeaking ? Colors.grey : Colors.blue,
                  child: Icon(
                    _isSpeaking ? Icons.pause : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  heroTag: "mic",
                  onPressed: () {
                    _flutterTts.stop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            QueryResponseScreen(initialLangCode: _langCode),
                      ),
                    );
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.mic, color: Colors.white),
                ),
              ],
            ),
          ),

          // ✅ Blur overlay on top of everything (including FABs)
          if (isLoading)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
