import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/holiday.dart';

class HolidayApiService {
  static const String apiUrl = 'http://172.23.176.1:5000/api/PublicHolidayApi/getpublicholidays';

  Future<List<Holiday>> getPublicHolidays() async {
    final response = await http.get(Uri.parse(apiUrl));

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((item) => Holiday.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load holidays');
    }
  }

    Future<bool> postHoliday(Holiday holiday) async {
        final url = Uri.parse('http://172.23.176.1:5000/api/PublicHolidayApi/postpublicholidays');
        final headers = {'Content-Type': 'application/json'};

        final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(holiday.toJson()),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
        print("✅ Successfully added holiday");
        return true;
        } else {
        print("❌ Error: ${response.statusCode} → ${response.body}");
        return false;
        }
    }
}
