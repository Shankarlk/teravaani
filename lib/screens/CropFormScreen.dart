import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';

class PostHarvestFormScreen extends StatefulWidget {
  final String userId; // pass this from previous screen or auth

  const PostHarvestFormScreen({required this.userId, Key? key}) : super(key: key);

  @override
  State<PostHarvestFormScreen> createState() => _PostHarvestFormScreenState();
}

class _PostHarvestFormScreenState extends State<PostHarvestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _cropName;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _startConnectivityListener();
  }

  void _startConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (result != ConnectivityResult.none) {
        _syncOfflineData();
      }
    });
  }

  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> _syncOfflineData() async {
    final List<Map<String, dynamic>> pendingEvents =
        await DatabaseHelper().getOfflinePostHarvestEvents();

    for (var event in pendingEvents) {
      final response = await http.post(
        Uri.parse("https://teravaanii-hggpe8btfsbedfdx.canadacentral-01.azurewebsites.net/api/generate-calendar"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": event['userId'],
          "cropName": event['cropName'],
          "sowingDate": event['sowingDate'],
          "noOfPlants": 0,
        }),
      );

      if (response.statusCode == 200) {
        await DatabaseHelper().deleteOfflinePostHarvestEvent(event['id']);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Saved Online.")),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    _formKey.currentState!.save();
    final String cropName = _cropName!;
    final String formattedDate = _selectedDate!.toIso8601String();
    final String userId = widget.userId;

    if (await _isOnline()) {
      final response = await http.post(
        Uri.parse("http://172.20.10.5:3000/api/generate-calendar"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "cropName": cropName,
          "sowingDate": formattedDate,
          "noOfPlants": 0,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Synced successfully!")),
        );
      } else {
        await DatabaseHelper().insertOfflinePostHarvestEvent(userId, cropName, formattedDate);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved offline, sync failed.")),
        );
      }
    } else {
      await DatabaseHelper().insertOfflinePostHarvestEvent(userId, cropName, formattedDate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Saved offline, will sync later.")),
      );
    }

    _formKey.currentState!.reset();
    setState(() => _selectedDate = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Post Harvest Form")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: InputDecoration(labelText: "Crop Name"),
                validator: (val) =>
                    val == null || val.isEmpty ? "Enter crop name" : null,
                onSaved: (val) => _cropName = val,
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedDate == null
                          ? "No Date Selected"
                          : "Sowing Date: ${_selectedDate!.toLocal().toIso8601String().split("T").first}",
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    child: Text("Select Date"),
                  ),
                ],
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submitForm,
                child: Text("Submit"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
