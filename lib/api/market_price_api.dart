import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/market_price.dart';

class MarketPriceApiService {
  final String _apiKey = '579b464db66ec23bdd0000012f9f5ca49425420d5fad6117bd37eab3';

  Future<List<MarketPrice>> fetchPrices() async {
    final url = Uri.parse(
      'https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070?api-key=579b464db66ec23bdd0000012f9f5ca49425420d5fad6117bd37eab3&format=json&limit=10000',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List records = json.decode(response.body)['records'];
      print(records.map((json) => MarketPrice.fromJson(json)).toList());
      return records.map((json) => MarketPrice.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch market prices');
    }
  }
}
