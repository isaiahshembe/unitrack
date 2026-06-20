import 'package:flutter/material.dart';
import 'package:uni_track/administration/admin_loginpage.dart';
import 'package:uni_track/super_administration/pages/add_admin.dart';
import 'package:uni_track/super_administration/pages/add_college.dart';
import 'package:uni_track/super_administration/pages/add_course.dart';
import 'package:uni_track/super_administration/pages/add_department.dart';
import 'package:uni_track/super_administration/pages/add_issue_priorities.dart';
import 'package:uni_track/super_administration/pages/add_issues_category.dart';
import 'package:uni_track/super_administration/pages/add_office.dart';
import 'package:uni_track/super_administration/pages/assign_offices.dart';

class SuperAdminHomepage extends StatefulWidget {
  const SuperAdminHomepage({super.key});

  @override
  State<SuperAdminHomepage> createState() => _SuperAdminHomepageState();
}

class _SuperAdminHomepageState extends State<SuperAdminHomepage> {
  // Method to show logout confirmation dialog
  Future<void> _showLogoutDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await _performLogout();
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  // Method to perform logout
  Future<void> _performLogout() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logging out...'),
        duration: Duration(seconds: 1),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AdminLoginpage()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Super Admin Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: const Icon(Icons.logout, size: 24),
              onPressed: _showLogoutDialog,
              tooltip: 'Logout',
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.green[50]!,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header Section with Stats or Welcome Message
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green[100]!,
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.admin_panel_settings,
                              size: 30,
                              color: Colors.green[800],
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome Back!',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[800],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Manage your university system from here',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Menu Items Grid
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.1,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    _buildMenuItem(
                      icon: Icons.school,
                      title: 'Add College',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const AddCollege()),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.account_tree,
                      title: 'Add Department',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) => const AddDepartment()),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.book,
                      title: 'Add Course',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const AddCourse()),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.priority_high,
                      title: 'Issue Priorities',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) => const AddIssuePriorities()),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.category,
                      title: 'Issue Categories',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) => const AddIssuesCategory()),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.business,
                      title: 'Add Office',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const AddOffice()),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.admin_panel_settings,
                      title: 'Add Admin',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const AddAdmin()),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.assignment_ind,
                      title: 'Assign Office',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) => const AssignOffices()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey[200]!,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
