import 'package:flutter/material.dart';
import 'package:scraper/theme.dart';
import 'package:scraper/screens/scraper_dashboard.dart';

void main() {
  runApp(const ScraperApp());
}

class ScraperApp extends StatelessWidget {
  const ScraperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Scraper & Repository Analyzer',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const ScraperDashboard(),
    );
  }
}
