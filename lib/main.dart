import 'package:flutter/material.dart';
import 'pages/wifi_blynk_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blynk Wi-Fi Controller',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const WifiBlynkPage(),
    );
  }
}