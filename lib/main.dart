import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/database_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MagrApp());
}

class MagrApp extends StatelessWidget {
  const MagrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAGR App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

