import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:teravaani/main.dart';
import 'package:teravaani/screens/query_response_screen.dart';
import '../api/market_price_api.dart';
import '../models/market_price.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../api/pageapi.dart';

const Map<String, List<String>> commodityCategories = {
  'Vegetables': [
    'Onion',
    'Potato',
    'Tomato',
    'Cabbage',
    'Brinjal',
    'Ginger(Dry)',
    'Bitter gourd',
    'Bottle gourd',
    'Carrot',
    'Cucumbar(Kheera)',
    'Ginger(Green)',
    'Ridgeguard(Tori)',
    'Seemebadnekai',
    'Suvarna Gadde',
    'Beans',
    'Cauliflower',
    'Green Chilli',
    'Snakeguard',
    'Ashgourd',
    'Capsicum',
    'Drumstick',
    'Knool Khol',
    'Sweet Pumpkin',
    'Thondekai',
    'Beetroot',
    'Bhindi(Ladies Finger)',
    'Chilly Capsicum',
    'Cluster beans',
    'Cowpea(Veg)',
    'Cowpea (Lobia/Karamani)',
    'French Beans (Frasbean)',
    'Indian Beans (Seam)',
    'Round gourd',
    'Pointed gourd (Parval)',
    'Little gourd (Kundru)',
    'Long Melon(Kakri)',
    'Pumpkin',
    'Raddish',
    'Seemebadnekai',
    'Suvarna Gadde',
    'Sweet Potato',
    'Tinda',
    'Turnip',
    'Sponge gourd',
    'Snakeguard',
    'Ashgourd',
    'Colacasia',
    'Chow Chow',
    'Knool Khol',
    'Amaranthus',
    'Amranthas Red',
    'Alsandikai',
    'Bunch Beans',
    'Duster Beans',
    'Leafy Vegetable',
    'Mashrooms',
  ],
  'Fruits': [
    'Apple',
    'Banana',
    'Banana - Green',
    'Mango',
    'Mango (Raw-Ripe)',
    'Pomegranate',
    'Karbuja(Musk Melon)',
    'Pineapple',
    'Water Melon',
    'Guava',
    'Papaya',
    'Papaya (Raw)',
    'Chikoos(Sapota)',
    'Jack Fruit',
    'Custard Apple (Sharifa)',
    'Amla(Nelli Kai)',
    'Jamun(Narale Hannu)',
    'Orange',
    'Peach',
    'Pear(Marasebu)',
    'Litchi',
    'Seetapal',
    'Fig(Anjura/Anjeer)',
    'Plum',
    'Apricot(Jardalu/Khumani)',
    'Lime',
  ],
  'Pulses': [
    'Arhar (Tur/Red Gram)(Whole)',
    'Arhar Dal(Tur Dal)',
    'Green Gram (Moong)(Whole)',
    'Green Gram Dal (Moong Dal)',
    'Black Gram (Urd Beans)(Whole)',
    'Black Gram Dal (Urd Dal)',
    'Bengal Gram(Gram)(Whole)',
    'Bengal Gram Dal (Chana Dal)',
    'Peas(Dry)',
    'Peas Wet',
    'Kabuli Chana(Chickpeas-White)',
    'Mataki',
    'Moath Dal',
    'Lentil (Masur)(Whole)',
    'Masur Dal',
    'Kulthi(Horse Gram)',
    'White Peas',
    'Field Pea',
  ],
  'Grains': [
    'Wheat',
    'Rice',
    'Maize',
    'Barley (Jau)',
    'Jowar(Sorghum)',
    'Bajra(Pearl Millet/Cumbu)',
    'Foxtail Millet(Navane)',
    'Kodo Millet(Varagu)',
    'Ragi (Finger Millet)',
    'Hybrid Cumbu',
    'Millets',
    'Paddy(Dhan)(Basmati)',
    'Paddy(Dhan)(Common)',
  ],
  'Species': [
    'Ginger(Dry)',
    'Ginger(Green)',
    'Garlic',
    'Turmeric',
    'Turmeric (raw)',
    'Cummin Seed(Jeera)',
    'Corriander seed',
    'Mint(Pudina)',
    'Methi Seeds',
    'Methi(Leaves)',
    'Chili Red',
    'Dry Chillies',
    'Pepper garbled',
    'Pepper ungarbled',
    'Black pepper',
    'Cardamoms',
    'Coriander(Leaves)',
    'Isabgul (Psyllium)',
    'Basil',
    'Ajwan',
    'Cinnamon(Dalchini)',
    'Mustard',
    'nigella seeds',
    'Safflower',
    'Soanf',
    'Suva (Dill Seed)',
    'Taramira',
    'Sesamum(Sesame,Gingelly,Til)',
    'Asalia',
    'Rayee',
    'Kutki',
    'Asgand',
    'Ashwagandha',
    'Muleti',
    'Castor Seed',
  ],
  'Others': [
    'Tender Coconut',
    'Betal Leaves',
    'Rubber',
    'Cotton',
    'Firewood',
    'Wood',
    'Lotus',
    'Lotus Sticks',
    'Season Leaves',
    'Dry Mango',
    'Mango Powder',
    'Raibel',
    'Rajgir',
    'Pegeon Pea (Arhar Fali)',
    'Poppy Seeds',
    'Mint(Pudina)',
    'Mahua',
    'Mahua Seed(Hippe seed)',
    'Hippe Seed',
    'BOP',
    'buttery',
    'Cock',
    'gulli',
    'Mahedi',
    'Patti Calcutta',
    'Thogrikai',
    'Gur(Jaggery)',
    'Sugar',
    'Sugarcane',
    'Coconut',
  ],
};

class MarketPriceScreen extends StatefulWidget {
  final String userDistrict;
  final String userState;

  MarketPriceScreen({required this.userDistrict, required this.userState});

  @override
  _MarketPriceScreenState createState() => _MarketPriceScreenState();
}

class _MarketPriceScreenState extends State<MarketPriceScreen>
    with WidgetsBindingObserver {
  final apiService = MarketPriceApiService();
  String selectedCategory = 'Vegetables';
  List<MarketPrice> filteredPrices = [];
  List<MarketPrice> allfecthState = [];
  bool isLoading = false;
  String selectedDistrict = '';
  List<String> markets = [];
  Map<String, String> translatedMarkets = {};
  String? selectedMarket;
  late String _currentLangCode;
  late FlutterTts flutterTts;
  Set<int> visibleRowIndexes = {};
  bool _isSpeaking = false;
  bool _isPaused = false;
  int lastSpokenRowIndex = -1;
  String labelCategory = "Category";
  String labelMarket = "Market";
  String labelCrop = "Crop";
  String labelMin = "Min Price";
  String labelMax = "Max Price";
  String labelModal = "Modal Price";
  String labelEmptyState = "No prices found";
  String labelAppBarTitle = "Market Rates";
  Map<String, String> translatedCommodities = {};
  Map<String, String> translatedCategories = {};
  List<String> translatedVisibleSentences = [];
  final Map<String, String> marketTranslations = {
    'Chickkaballapura (Chickkaballapura)': 'Chickkaballapura (ಚಿಕ್ಕಬಳ್ಳಾಪುರ)',
    'Chikkamagalore (Chikkamagalore)': 'Chikkamagalore (ಚಿಕ್ಕಮಗಳೂರು)',
    'Gowribidanoor (Gowribidanoor)': 'Gowribidanoor (ಗೌರಿಬಿದನೂರು)',
    'Kottur (Kottur)': 'Kottur (ಕೋಟೂರು)',
    'Bantwala (Bantwala)': 'Bantwala (ಬಂಟ್ವಾಳ)',
    'Belthangdi (Belthangdi)': 'Belthangdi (ಬೆಳ್ತಂಗಡಿ)',
    'Kudchi (Kudchi)': 'Kudchi (ಕುಡಚಿ)',
    'Haliyala (Haliyala)': 'Haliyala (ಹಳಿಯಾಳ)',
    'Kumta (Kumta)': 'Kumta (ಕುಮಟಾ)',
    'Kalagategi (Kalagategi)': 'Kalagategi (ಕಲಗಟೇಗಿ)',
    'Kalburgi (Kalburgi)': 'Kalburgi (ಕಲ್ಬುರ್ಗಿ)',
    'Mulabagilu (Mulabagilu)': 'Mulabagilu (ಮುಳಬಾಗಿಲು)',
    'Malur (Malur)': 'Malur (ಮಾಲೂರು)',
    'Sankeshwar (Sankeshwar)': 'Sankeshwar (ಸಂಕೇಶ್ವರ)',
    'Shimogga(Theertahalli) (Shimogga (theertahalli))':
        'Shimogga(Theertahalli) (ಶಿವಮೊಗ್ಗ (ತೀರ್ಥಹಳ್ಳಿ))',
    'Sulya (Sulya)': 'Sirsi (ಸುಳ್ಯ)',
    'Sirsi (Sirsi)': 'Sirsi (ಸಿರಸಿ)',
    'Sorabha (Sorabha)': 'Sorabha (ಸೋರಭ)',
    'Srinivasapur (Srinivasapur)': 'Srinivaspur (ಶ್ರೀನಿವಾಸಪುರ)',
    'Yellapur (Yellapur)': 'Yellapur (ಯಲ್ಲಾಪುರ)',
  };

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
    _currentLangCode = 'kn';
    selectedDistrict = widget.userDistrict.replaceAll('Division', '').trim();
    flutterTts = FlutterTts();
    _initTTSHandlers();
    _initTts();
    _translateStaticLabels();
    _translateCategoryLabels(); // Add this
    _loadMarketsAndThenFetch();
    PageAPI.logPageVisit("MarketPriceScreen");
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
      _currentLangCode,
    );
    final almsg = await _translateToNativeLanguage("Alert", _currentLangCode);
    final okmsg = await _translateToNativeLanguage("OK", _currentLangCode);

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

  void _initTTSHandlers() {
    flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    });

    flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    });

    flutterTts.setPauseHandler(() {
      setState(() {
        _isSpeaking = false;
        _isPaused = true;
      });
    });

    flutterTts.setContinueHandler(() {
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    });

    flutterTts.setCancelHandler(() {
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    });
  }

  Future<void> _loadMarketsAndThenFetch() async {
    setState(() => isLoading = true); // Begin loading
    await _loadMarkets(); // ⏳ wait for markets and selectedMarket
    setState(() => isLoading = false); // Done loading
    //await _fetchAndFilter(); // ✅ now filter based on correct market
    setState(() => isLoading = false);
  }

  void _translateStaticLabels() async {
    labelAppBarTitle = await translateLabel("Market Rates");
    labelCategory = await translateLabel("Commodities");
    labelMarket = await translateLabel("Market");
    labelCrop = await translateLabel("Crop");
    labelMin = await translateLabel("Min Price");
    labelMax = await translateLabel("Price");
    labelModal = await translateLabel("Modal Price");
    labelEmptyState = await translateLabel(
      "No Rates found for $selectedMarket in $selectedCategory.",
    );

    setState(() {}); // Rebuild UI with translated labels
  }

  Future<void> _translateCategoryLabels() async {
    translatedCategories.clear();
    final translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _getMLKitLanguage(_currentLangCode),
    );

    for (String category in commodityCategories.keys) {
      try {
        final native = await translator.translateText(category);
        translatedCategories[category] = "$category ($native)";
      } catch (_) {
        translatedCategories[category] = category;
      }
    }

    await translator.close();
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove observertions
    flutterTts.stop(); // Stop any ongoing speech
    super.dispose();
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

  Future<void> _initTts() async {
    // Set TTS language, rate, and pitch for natural speech
    await flutterTts.setLanguage(_currentLangCode);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _speakText(String text) async {
    await flutterTts.setLanguage(_currentLangCode);
    await flutterTts.speak(text);
  }

  Future<void> _loadMarkets() async {
    try {
      final fetchedMarkets = await apiService.fetchMarkets(
        state: widget.userState,
      );
      print('fetchedMarkets $fetchedMarkets');

      // Translate market names
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(_currentLangCode),
      );

      Map<String, String> translations = {};
      for (String market in fetchedMarkets) {
        try {
          String native = await translateToNative(market);
          String trantxt = "$market ($native)";
          trantxt = marketTranslations[trantxt] ?? trantxt;
          translations[market] = trantxt;
        } catch (_) {
          translations[market] = market;
        }
      }

      await translator.close();

      setState(() {
        markets = fetchedMarkets;
        translatedMarkets = translations;

        selectedMarket = (markets.isNotEmpty)
            ? markets.firstWhere(
                (m) => m.toLowerCase().contains(
                  widget.userDistrict
                      .replaceAll('Division', '')
                      .trim()
                      .toLowerCase(),
                ),
                orElse: () => markets.first,
              )
            : '';
      });
    } catch (e) {
      print("❌ Error loading markets: $e");
      String responseMessageNt = await translateToNative(
        "Service unavailable. Please try again later.",
      );
      final almsg = await translateToNative("Alert");
      final okmsg = await translateToNative("ok");
      setState(() {});
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("Alert\n($almsg)"),
            content: Text(
              "Service unavailable. Please try again later.\n($responseMessageNt)",
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
        await flutterTts.speak(responseMessageNt);
      }
    }
  }

  Future<void> _speakVisibleTranslatedRows() async {
    final visibleIndexes = visibleRowIndexes.toList()..sort();

    if (visibleIndexes.isEmpty || translatedVisibleSentences.isEmpty) {
      print("⚠️ No visible rows or translated sentences to speak.");
      return;
    }

    final List<String> visibleSentences = [];

    for (int i in visibleIndexes) {
      if (i < translatedVisibleSentences.length) {
        visibleSentences.add(translatedVisibleSentences[i]);
      }
    }

    final textToRead = visibleSentences.join(' ');
    if (textToRead.trim().isNotEmpty) {
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
      await flutterTts.stop();
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);
      await flutterTts.speak(textToRead);
    }
  }

  Future<void> _fetchAndFilter() async {
    if (isLoading) return; // prevent double loading
    setState(() => isLoading = true);

    try {
      final allPrices = await apiService.fetchPrices(state: widget.userState);
      allfecthState = allPrices.toList();

      final keywords = commodityCategories[selectedCategory] ?? [];
      final today = DateTime.now();
      final selectedMarketLower = (selectedMarket ?? '').toLowerCase();
      final selectedStateLower = widget.userState.toLowerCase();

      bool matches(MarketPrice p, DateTime d) {
        return p.market.toLowerCase().contains(selectedMarketLower) &&
            p.state.toLowerCase().contains(selectedStateLower) &&
            p.date?.toLocal().day == d.day &&
            p.date?.toLocal().month == d.month &&
            p.date?.toLocal().year == d.year &&
            keywords.any(
              (k) => p.commodity.toLowerCase().contains(k.toLowerCase()),
            );
      }

      // ✅ Try today's data
      final todayData = allPrices.where((p) => matches(p, today)).toList();

      if (todayData.isNotEmpty) {
        await _translateCommoditiesFor(todayData);
        setState(() {
          filteredPrices = todayData;
        });
        await _fetchAndTranslateData();
        print("✅ Showing today's data: ${filteredPrices.length}");
        return;
      }

      // ✅ Try yesterday's data only
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayData = allPrices
          .where((p) => matches(p, yesterday))
          .toList();

      if (yesterdayData.isNotEmpty) {
        await _translateCommoditiesFor(yesterdayData);
        setState(() {
          filteredPrices = yesterdayData;
        });

        final fallbackStr = yesterday.toLocal().toString().split(' ')[0];
        final confirmationEnglish =
            "Today's prices are not available. Showing yesterday's data from $fallbackStr.";
        final confirmationNative = await translateToNative(confirmationEnglish);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text("Old Data"),
              content: Text("$confirmationEnglish \n ($confirmationNative)"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        });

        _speakText(confirmationNative);
        await _fetchAndTranslateData();
        print("⚠️ Showing yesterday's data: ${filteredPrices.length}");
        return;
      }

      // ❌ Neither today nor yesterday available
      setState(() {
        filteredPrices = [];
      });

      final msgEng = "No Prices found for this category and market.";
      final msgNative = await translateToNative(msgEng);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("No Data"),
            content: Text("$msgEng\n($msgNative)"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      });

      _speakText(msgNative);
    } catch (e) {
      print('Error fetching prices: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _translateCommoditiesFor(List<MarketPrice> prices) async {
    translatedCommodities.clear();

    final uniqueCommodities = prices.map((p) => p.commodity).toSet();

    final translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _getMLKitLanguage(_currentLangCode),
    );

    for (var name in uniqueCommodities) {
      try {
        final native = await translator.translateText(name);
        translatedCommodities[name] = "$name\n($native)";
      } catch (e) {
        translatedCommodities[name] = name; // fallback if error
      }
    }

    await translator.close();
  }

  Future<String> translateToNative(String text) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(_currentLangCode),
      );
      final translated = await translator.translateText(text);
      await translator.close(); // Close translator to release resources
      return translated;
    } catch (e) {
      print("❌ Translation to native failed: $e");
      return text; // Return original text on failure
    }
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
        return TranslateLanguage.english; // Default to English
    }
  }

  String formatPrice(double? price) {
    if (price == null) return 'N/A';
    double perKg = price / 100.0;
    return "₹${perKg.toStringAsFixed(2)}/Kg";
  }

  Future<void> _togglePlayPause() async {
    if (_isSpeaking) {
      await flutterTts.pause();
      setState(() {
        _isSpeaking = false;
        _isPaused = true;
      });
    } else {
      final visibleRows = visibleRowIndexes.toList()..sort();
      final textsToSpeak = visibleRows
          .map((i) {
            final p = filteredPrices[i];
            return "${p.commodity}: Minimum ${formatPrice(p.minPrice)}, Maximum ${formatPrice(p.maxPrice)}, Common ${formatPrice(p.modalPrice)}";
          })
          .join(". ");

      if (textsToSpeak.trim().isNotEmpty) {
        await _speakVisibleRows(textsToSpeak);
      }

      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    }
  }

  Future<void> _speakVisibleRows(String text) async {
    await flutterTts.stop();
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
    await flutterTts.speak(text);
  }

  Future<String> translateLabel(String english) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(_currentLangCode),
      );
      final translated = await translator.translateText(english);
      await translator.close();
      return "$english \n($translated)";
    } catch (e) {
      print("❌ Label translation failed: $e");
      return english;
    }
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

  Future<String> translateCommodity(String name) async {
    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: _getMLKitLanguage(_currentLangCode),
      );
      final native = await translator.translateText(name);
      await translator.close();
      return "$name \n($native)";
    } catch (_) {
      return name;
    }
  }

  Future<void> _fetchAndTranslateData() async {
    final labelPrice = await translateToNative("Price");
    final translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _getMLKitLanguage(_currentLangCode),
    );

    translatedVisibleSentences.clear();

    for (var p in filteredPrices) {
      final sentence =
          "${p.commodity}: $labelPrice ${formatPrice(p.maxPrice)}.";
      try {
        final translated = await translator.translateText(sentence);
        translatedVisibleSentences.add(translated);
      } catch (_) {
        translatedVisibleSentences.add(sentence); // fallback
      }
    }

    await translator.close();

    setState(() {}); // ensure UI updates with translations

    // ✅ Give time for the UI to render and VisibilityDetector to register

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 500)); // 🟡 ADD SMALL DELAY
      print("🗣️ Trying to speak after translation + visibility detection...");
      _speakVisibleTranslatedRows();
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
          backgroundColor: Colors.green,
          iconTheme: const IconThemeData(
            color: Colors.white, // Back button color
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // 📝 Title (Aligned Left)
              Expanded(
                child: Text(
                  labelAppBarTitle,
                  style: const TextStyle(
                    color: Colors.white, // White text color
                    fontWeight: FontWeight.w700, // Bold
                    fontSize: 20, // Title size
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // 🌱 Logo on Right
              Image.asset(
                "assets/logo.png", // Update to your actual logo path
                height: 70, // Adjust height
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),

        body: Column(
          children: [
            // 🔹 Category & Market Dropdown Section
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              child: Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== CATEGORY DROPDOWN =====
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Text(
                        labelCategory,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: DropdownButtonFormField<String>(
                        value: selectedCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            selectedCategory = val!;
                          });
                          _fetchAndFilter();
                        },
                        items: commodityCategories.keys.map((category) {
                          final displayLabel =
                              translatedCategories[category] ?? category;
                          return DropdownMenuItem(
                            value: category,
                            child: Text(
                              displayLabel,
                              style: const TextStyle(fontSize: 15),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(
                      height: 16,
                    ), // Space between Category and Market
                    // ===== MARKET DROPDOWN =====
                    if (markets.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Text(
                          labelMarket,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButtonFormField<String>(
                          value: selectedMarket,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {
                              selectedMarket = val!;
                            });
                            _fetchAndFilter();
                          },
                          items: markets.map((market) {
                            final displayLabel =
                                translatedMarkets[market] ?? market;
                            return DropdownMenuItem(
                              value: market,
                              child: Text(
                                displayLabel,
                                style: const TextStyle(fontSize: 15),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 🔹 Price Listing Section
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredPrices.isEmpty
                  ? Center(
                      child: FutureBuilder<String>(
                        future: translateLabel(
                          "No prices found for $selectedMarket in $selectedCategory.",
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const CircularProgressIndicator();
                          } else if (snapshot.hasError) {
                            return const Text("Error");
                          } else {
                            return Text(snapshot.data ?? "Translation failed");
                          }
                        },
                      ),
                    )
                  : Column(
                      children: [
                        // Sticky Header
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 20,
                                  ), // Add left padding here
                                  child: Text(
                                    labelCrop,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 10,
                                  ), // Add left padding here
                                  child: Text(
                                    labelMax,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // List of prices
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: filteredPrices.length,
                            itemBuilder: (context, index) {
                              final p = filteredPrices[index];
                              return VisibilityDetector(
                                key: Key("row_$index"),
                                onVisibilityChanged: (info) {
                                  if (info.visibleFraction > 0) {
                                    visibleRowIndexes.add(index);
                                  } else {
                                    visibleRowIndexes.remove(index);
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),

                                  child: Row(
                                    children: [
                                      // 🌾 Commodity Image
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          8,
                                        ), // Rounded edges
                                        child: Image.network(
                                          "http://172.20.10.5:3000/cropsimg/${p.commodity}.jpg", // Keep the space in name
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  width: 50,
                                                  height: 50,
                                                  color: Colors.grey.shade200,
                                                  child: const Icon(
                                                    Icons.image_not_supported,
                                                    color: Colors.grey,
                                                  ),
                                                );
                                              },
                                        ),
                                      ),

                                      const SizedBox(
                                        width: 12,
                                      ), // spacing between image and text
                                      // 🌿 Commodity Name
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          translatedCommodities[p.commodity] ??
                                              p.commodity,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),

                                      // 💰 Max Price
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          formatPrice(p.maxPrice),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              onPressed: () async {
                if (_isSpeaking) {
                  await flutterTts.pause();
                  setState(() {
                    _isSpeaking = false;
                    _isPaused = true;
                  });
                } else {
                  final visibleIndexes = visibleRowIndexes.toList()..sort();

                  if (visibleIndexes.isEmpty ||
                      translatedVisibleSentences.isEmpty)
                    return;

                  // Use only currently visible translated sentences
                  final List<String> visibleSentences = [];

                  for (int i in visibleIndexes) {
                    if (i < translatedVisibleSentences.length) {
                      visibleSentences.add(translatedVisibleSentences[i]);
                    }
                  }

                  final textToRead = visibleSentences.join(' ');
                  if (textToRead.trim().isNotEmpty) {
                    await flutterTts.stop();
                    await flutterTts.setSpeechRate(0.5);
                    await flutterTts.setVolume(1.0);
                    await flutterTts.setPitch(1.0);
                    await flutterTts.speak(textToRead);

                    setState(() {
                      _isSpeaking = true;
                      _isPaused = false;
                    });
                  }
                }
              },
              backgroundColor: _isSpeaking ? Colors.grey : Colors.blue,
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        QueryResponseScreen(initialLangCode: _currentLangCode),
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
}
