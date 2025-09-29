class CropEvent {
  final String eventType;
  final String scheduledDate;

  CropEvent({
    required this.eventType,
    required this.scheduledDate,
  });

  factory CropEvent.fromJson(Map<String, dynamic> json) {
    return CropEvent(
      eventType: json['EventType'] ?? '',
      scheduledDate: json['ScheduledDate'] ?? '',
    );
  }
}
