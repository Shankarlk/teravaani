class Holiday {
  final int id;
  final String name;
  final DateTime date;
  final bool isEvent;
  final bool isExam;
  final bool isActive;

  Holiday({
    required this.id,
    required this.name,
    required this.date,
    required this.isEvent,
    required this.isExam,
    required this.isActive,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    return Holiday(
      id: json['id'],
      name: json['holidayOrEventName'],
      date: DateTime.parse(json['holidayDate']),
      isEvent: json['isEvent'],
      isExam: json['examination'],
      isActive: json['isActive'],
    );
  }
  Map<String, dynamic> toJson() {
    return {
    'id': id,
    'holidayOrEventName': name,
    'holidayDate': date.toIso8601String(),
    'isEvent': isEvent,
    'examination': isExam,
    'isActive': isActive,
    'isDeleted': false, // Add this since your ViewModel expects it
    };
    }
}
