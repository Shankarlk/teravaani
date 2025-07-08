class MarketPrice {
  final String state;
  final String district;
  final String market;
  final String commodity;
  final String variety;
  final String arrivalDate;
  final String minPrice;
  final String maxPrice;
  final String modalPrice;

  MarketPrice({
    required this.state,
    required this.district,
    required this.market,
    required this.commodity,
    required this.variety,
    required this.arrivalDate,
    required this.minPrice,
    required this.maxPrice,
    required this.modalPrice,
  });

  factory MarketPrice.fromJson(Map<String, dynamic> json) {
    return MarketPrice(
      state: json['state'],
      district: json['district'],
      market: json['market'],
      commodity: json['commodity'],
      variety: json['variety'],
      arrivalDate: json['arrival_date'],
      minPrice: json['min_price'],
      maxPrice: json['max_price'],
      modalPrice: json['modal_price'],
    );
  }
}
