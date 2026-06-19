import 'package:flutter/material.dart';
import 'package:uni_track/ai/ai_operations_page.dart';
import 'package:uni_track/administration/admin_homepage.dart';
import 'package:uni_track/administration/admin_issuespage.dart';
import 'package:uni_track/administration/admin_noticespage.dart';
import 'package:uni_track/administration/admin_profilepage.dart';

class AdminMainpage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const AdminMainpage({super.key, required this.userData});

  @override
  State<AdminMainpage> createState() => _AdminMainpageState();
}

class _AdminMainpageState extends State<AdminMainpage> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      AdminHomepage(
        adminData: widget.userData,
        onNavigateToIssues: _navigateToIssues,
        onNavigateToNotices: _navigateToNotices,
      ),
      AdminIssuesPage(adminData: widget.userData),
      AiOperationsPage(userData: widget.userData),
      AdminNoticesPage(adminData: widget.userData),
      AdminProfilepage(adminData: widget.userData),
    ];
  }

  void _navigateToIssues() {
    setState(() {
      _selectedIndex = 1;
    });
  }

  void _navigateToNotices() {
    setState(() {
      _selectedIndex = 3;
    });
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
              icon: Icon(Icons.auto_awesome_outlined),
              activeIcon: Icon(Icons.auto_awesome),
              label: 'AI',
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
