import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/address_model.dart';

class AddressListScreen extends StatefulWidget {
  const AddressListScreen({super.key});

  @override
  State<AddressListScreen> createState() => _AddressListScreenState();
}

class _AddressListScreenState extends State<AddressListScreen> {
  List<Address> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    fetchAddresses();
  }

  Future<void> fetchAddresses() async {
    try {
      final response = await http.get(Uri.parse('http://172.23.176.1:3000/api/address'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _addresses = data.map((json) => Address.fromJson(json)).toList();
          _loading = false;
        });
      } else {
        throw Exception('Failed to load addresses');
      }
    } catch (e) {
      print("❌ Error fetching addresses: $e");
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("📍 Address List")),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _addresses.length,
              itemBuilder: (context, index) {
                final address = _addresses[index];
                return Card(
                  child: ListTile(
                    title: Text("${address.addressLine1}, ${address.addressLine2}"),
                    subtitle: Text("${address.suburb} - ${address.postalCode}"),
                  ),
                );
              },
            ),
    );
  }
}
