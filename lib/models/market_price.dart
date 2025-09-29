class MarketPrice {
  final String state;
  final String district;
  final String market;
  final String commodity;
  final String variety;
  final double? modalPrice;
  final double? maxPrice;
  final double? minPrice;
  final DateTime? date;
  final String cropImage;

  MarketPrice({
    required this.state,
    required this.district,
    required this.market,
    required this.commodity,
    required this.variety,
    required this.modalPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.date,
    required this.cropImage,
  });

  factory MarketPrice.fromJson(Map<String, dynamic> json) {
    return MarketPrice(
      state: json['State'] ?? '',
      district: json['District'] ?? '',
      market: json['Market'] ?? '',
      commodity: json['Commodity'] ?? '',
      variety: json['Variety'] ?? '',
      minPrice: (json['MinPrice'] as num?)?.toDouble(),
      maxPrice: (json['MaxPrice'] as num?)?.toDouble(),
      modalPrice: (json['ModalPrice'] as num?)?.toDouble(),
      date: json['Date'] != null ? DateTime.tryParse(json['Date']) : null,
      cropImage: json['CropImage'] ?? '',
    );
  }
}
