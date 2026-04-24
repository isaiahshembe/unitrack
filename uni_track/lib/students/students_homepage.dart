import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  final Map<String, dynamic> userData;
  const HomePage({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Student Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Center(
        child: Text(
          'Welcome ${userData['full_name'] ?? 'Student'}!',
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ),
    );
  }
}