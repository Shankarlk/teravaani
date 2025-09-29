// lib/api/pageapi.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class PageAPI {
  static String? userDistrict;
  static String? userState;

  /// Should be set from `_getLocation()` in main.dart after fetching
  static void setLocation({required String district, required String state}) {
    userDistrict = district;
    userState = state;
  }

  static Future<void> logPageVisit(String pageName) async {
    try {
      final deviceId = await getOrCreateDeviceId();
      
      // Get Location
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // Reverse Geocode to get full address
      List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);

      Placemark place = placemarks[0];
      String fullAddress =
          "${place.name}, ${place.street}, ${place.subLocality}, ${place.locality}, ${place.administrativeArea}, ${place.postalCode}, ${place.country}";

        print("Full Address: ${fullAddress}");
      final data = {
        'device_id': deviceId,
        'district': userDistrict ?? 'unknown',
        'state': userState ?? 'unknown',
        'pagename': pageName,
        'timestamp': DateTime.now().toIso8601String(),
        'full_address': fullAddress,
      };

      final response = await http.post(
        Uri.parse('http://172.20.10.5:3000/api/log-page-visit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        print("✅ Page visit logged: $pageName");
      } else {
        print("❌ Failed to log page visit: ${response.body}");
      }
    } catch (e) {
      print("❌ Exception logging page visit: $e");
    }
  }
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      deviceId = const Uuid().v4(); // Generate UUID
      await prefs.setString('device_id', deviceId);
    }

    return deviceId;
  }
}
