class Address {
  final int id;
  final String addressLine1;
  final String addressLine2;
  final String suburb;
  final String postalCode;

  Address({
    required this.id,
    required this.addressLine1,
    required this.addressLine2,
    required this.suburb,
    required this.postalCode,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: json['Id'],
      addressLine1: json['AddressLine1'],
      addressLine2: json['AddressLine2'],
      suburb: json['Suburb'],
      postalCode: json['PostalCode'],
    );
  }
}
