import 'package:flutter/material.dart';

import 'package:uni_track/students/students_homepage.dart';
import 'package:uni_track/students/students_issuespage.dart';
import 'package:uni_track/students/students_noticespage.dart';
import 'package:uni_track/students/students_profilepage.dart';

class StudentsMainpage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const StudentsMainpage({super.key, required this.userData});

  @override
  State<StudentsMainpage> createState() => _StudentsMainpageState();
}

class _StudentsMainpageState extends State<StudentsMainpage> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(userData: widget.userData),
      IssuesPage(userData: widget.userData),
      const NoticesPage(),
      ProfilePage(userData: widget.userData),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey[200]!,
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          selectedItemColor: Colors.green,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 12,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.warning_amber_outlined),
              activeIcon: Icon(Icons.warning_amber),
              label: 'Issues',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none),
              activeIcon: Icon(Icons.notifications),
              label: 'Notices',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
