import 'package:flutter/material.dart';
import '../api/holiday_api_service.dart';
import '../models/holiday.dart';
import 'package:intl/intl.dart';

class HolidayListScreen extends StatelessWidget {
  final HolidayApiService _apiService = HolidayApiService();

  String formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

 @override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(title: Text('Public Holidays & Events')),
body: Column(
children: [
Padding(
padding: const EdgeInsets.all(8.0),
child: ElevatedButton.icon(
icon: Icon(Icons.add),
label: Text("Post Dummy Holiday"),
onPressed: () async {
final dummyHoliday = Holiday(
id: 0,
name: 'Demo Event',
date: DateTime.now().add(Duration(days: 3)),
isEvent: true,
isExam: false,
isActive: true,
);
          try {
            await _apiService.postHoliday(dummyHoliday);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("🎉 Dummy holiday posted")),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("❌ Failed to post: $e")),
            );
          }
        },
      ),
    ),
    Expanded(
      child: FutureBuilder<List<Holiday>>(
        future: _apiService.getPublicHolidays(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator());

          if (snapshot.hasError)
            return Center(child: Text('❌ ${snapshot.error}'));

          final holidays = snapshot.data!;
          holidays.sort((a, b) => a.date.compareTo(b.date));

          return ListView.builder(
            itemCount: holidays.length,
            itemBuilder: (context, index) {
              final holiday = holidays[index];
              return ListTile(
                leading: Icon(
                  holiday.isEvent ? Icons.event : Icons.beach_access,
                  color: holiday.isActive ? Colors.green : Colors.grey,
                ),
                title: Text(holiday.name),
                subtitle: Text(formatDate(holiday.date)),
                trailing: holiday.isExam
                    ? Icon(Icons.school, color: Colors.blue)
                    : null,
              );
            },
          );
        },
      ),
    ),
  ],
),
);
}
}
