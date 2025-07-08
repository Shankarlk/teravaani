import 'package:flutter/material.dart';
import '../api/market_price_api.dart';
import '../models/market_price.dart';

const Map<String, List<String>> commodityCategories = {
  'Vegetables': ['Onion', 'Potato', 'Tomato', 'Cabbage', 'Brinjal'],
  'Fruits': ['Apple', 'Banana', 'Mango', 'Grapes'],
  'Pulses': ['Green Gram', 'Black Gram', 'Red Gram'],
  'Grains': ['Wheat', 'Rice', 'Maize'],
};

class MarketPriceScreen extends StatefulWidget {
  final String userDistrict;
  final String userState;

  MarketPriceScreen({required this.userDistrict, required this.userState});

  @override
  _MarketPriceScreenState createState() => _MarketPriceScreenState();
}

class _MarketPriceScreenState extends State<MarketPriceScreen> {
  final apiService = MarketPriceApiService();
  String selectedCategory = 'Vegetables';
  List<MarketPrice> filteredPrices = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAndFilter();
  }

  Future<void> _fetchAndFilter() async {
    setState(() => isLoading = true);

    try {
      final allPrices = await apiService.fetchPrices();

      final district = widget.userDistrict.toLowerCase();
      final state = widget.userState.toLowerCase();
      final keywords = commodityCategories[selectedCategory] ?? [];

      print("Total Prices: ${allPrices.length}");
      print("Selected Catg: ${keywords}");
      print("Filtering for State: $state, District: $district");

      final locationFiltered = allPrices.where((p) {
  final pDistrict = p.district.toLowerCase();
  final pState = p.state.toLowerCase();
  return pDistrict.contains(district) && pState.contains(state);
}).toList();

      print("Location matched: ${locationFiltered.length}");

      setState(() {
        filteredPrices = locationFiltered.where((p) {
          return keywords.any((k) => p.commodity.toLowerCase().contains(k.toLowerCase()));
        }).toList();
      });

      print("Category matched: ${filteredPrices.length}");

    } catch (e) {
      print('Error fetching prices: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Market Prices")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<String>(
              value: selectedCategory,
              onChanged: (val) {
                setState(() => selectedCategory = val!);
                _fetchAndFilter();
              },
              items: commodityCategories.keys.map((category) {
                return DropdownMenuItem(value: category, child: Text(category));
              }).toList(),
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : filteredPrices.isEmpty
                    ? Center(child: Text("No prices found for ${widget.userDistrict}, ${widget.userState} in $selectedCategory."))
                    : ListView.builder(
                        itemCount: filteredPrices.length,
                        itemBuilder: (context, index) {
                          final p = filteredPrices[index];
                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              title: Text("${p.commodity} (${p.variety})"),
                              subtitle: Text("${p.market}, ${p.district}, ${p.state}"),
                              trailing: Text("₹${p.modalPrice}"),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
