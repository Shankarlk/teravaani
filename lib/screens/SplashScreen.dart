import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart'; // import VoiceHomePage from here

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // small delay so splash is visible
    await Future.delayed(const Duration(seconds: 2));

    // request location
    final locStatus = await Permission.location.request();

    if (locStatus.isGranted) {
      // if granted → go to VoiceHomePage
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => VoiceHomePage()),
      );
    } else {
      // if denied → show alert
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Location Required"),
          content: const Text("Please allow location to use TeraVaani."),
          actions: [
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text("Open Settings"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 84, 177, 87), // match your design
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              "assets/logo.png", // your splash image
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 20),
            const Text(
              " ",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
