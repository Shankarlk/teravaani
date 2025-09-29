import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/market_price.dart';

class MarketPriceApiService {
  final String baseUrls = 'http://172.20.10.5:3000/api'; // replace IP
  final String baseUrl = 'http://172.20.10.5:3000/api/market-prices'; // replace IP

  Future<List<MarketPrice>> fetchPrices({
    String? state,
    String? district,
    String? market,
    String? commodity,
  }) async {
    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      if (state != null) 'state': state,
      if (district != null) 'district': district,
      if (market != null) 'market': market,
      if (commodity != null) 'commodity': commodity,
    });

    final response = await http.get(uri).timeout(Duration(seconds: 20));
    print('get url : ${uri}');
    print('api response : ${response.body}');
    if (response.statusCode == 200) {
      final List<dynamic> jsonData = json.decode(response.body);
      return jsonData.map((e) => MarketPrice.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load market prices');
    }
  }

  Future<List<String>> fetchMarkets({String? state, String? district}) async {
    final uri = Uri.parse('$baseUrls/getallmarkets').replace(queryParameters: {
      if (state != null) 'state': state,
      if (district != null) 'district': district,
    });

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['markets']);
    } else {
      throw Exception('Failed to fetch markets');
    }
  }


}
