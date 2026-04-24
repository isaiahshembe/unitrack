import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddAdmin extends StatefulWidget {
  const AddAdmin({super.key});

  @override
  State<AddAdmin> createState() => _AddAdminState();
}

class _AddAdminState extends State<AddAdmin> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _admins = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAdmins();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _employeeIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchAdmins() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('admins')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      setState(() {
        _admins = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = _handleErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  String _handleErrorMessage(dynamic error) {
    if (error is PostgrestException) {
      if (error.code == '42P01') {
        return 'Table "admins" does not exist. Please create it in Supabase.';
      }
      if (error.code == '23505') {
        return 'An admin with this email or employee ID already exists.';
      }
      return 'Database error: ${error.message}';
    }
    if (error.toString().contains('User already registered')) {
      return 'An account with this email already exists.';
    }
    return 'Error: $error';
  }

  String _generateRandomPassword() {
    const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lowercase = 'abcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const specials = '!@#%^&*';

    final allChars = uppercase + lowercase + numbers + specials;
    final random = Random();

    String password = '';
    password += uppercase[random.nextInt(uppercase.length)];
    password += lowercase[random.nextInt(lowercase.length)];
    password += numbers[random.nextInt(numbers.length)];
    password += specials[random.nextInt(specials.length)];

    for (int i = 0; i < 8; i++) {
      password += allChars[random.nextInt(allChars.length)];
    }

    List<String> passwordList = password.split('');
    passwordList.shuffle(random);
    return passwordList.join();
  }

  Future<void> _addAdmin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final randomPassword = _generateRandomPassword();
    final email = _emailController.text.trim().toLowerCase();
    final fullName = _fullNameController.text.trim();
    final employeeId = _employeeIdController.text.trim();
    final phone = _phoneController.text.trim();

    try {
      // Step 1: Create auth user using regular sign up
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: randomPassword,
        data: {
          'full_name': fullName,
          'employee_id': employeeId,
          'phone': phone,
          'role': 'makerere_admin',
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create auth user');
      }

      final userId = authResponse.user!.id;

      // Step 2: Save admin to database
      final adminData = {
        'id': userId,
        'full_name': fullName,
        'email': email,
        'employee_id': employeeId,
        'phone': phone,
        'password': randomPassword,
        'role': 'makerere_admin',
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabase
          .from('admins')
          .insert(adminData)
          .timeout(const Duration(seconds: 10));

      // Clear form
      _fullNameController.clear();
      _emailController.clear();
      _employeeIdController.clear();
      _phoneController.clear();

      setState(() {
        _isSaving = false;
      });

      // Show password dialog
      await _showPasswordDialog(randomPassword, fullName, email);
      _showSnackBar('Admin created!', Colors.green);

      // Refresh list
      await _fetchAdmins();
    } catch (e) {
      print('Error creating admin: $e');
      setState(() {
        _errorMessage = _handleErrorMessage(e);
        _isSaving = false;
      });
      _showSnackBar(_handleErrorMessage(e), Colors.red);
    }
  }

  Future<void> _showPasswordDialog(
    String password,
    String adminName,
    String email,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text(
              'Admin Created!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin: $adminName',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            Text(
              'Email: $email',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Temporary Password:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: SelectableText(
                password,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Please securely share this password with the admin. They can change it after logging in.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              'OK',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(String id, String email, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Reset Password',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('Reset password for "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isSaving = true;
        _errorMessage = null;
      });

      final newPassword = _generateRandomPassword();

      try {
        // Send password reset email
        await _supabase.auth.resetPasswordForEmail(email);

        // Update password in admins table
        await _supabase
            .from('admins')
            .update({'password': newPassword})
            .eq('id', id)
            .timeout(const Duration(seconds: 10));

        setState(() {
          _isSaving = false;
        });

        // Show new password dialog
        await _showPasswordDialog(newPassword, name, email);
        _showSnackBar(
          'Password reset successfully! A reset email has been sent.',
          Colors.green,
        );
      } catch (e) {
        setState(() {
          _errorMessage = _handleErrorMessage(e);
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteAdmin(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete Admin',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isSaving = true;
        _errorMessage = null;
      });

      try {
        // Delete from admins table only (auth user remains but can be deleted manually)
        await _supabase
            .from('admins')
            .delete()
            .eq('id', id)
            .timeout(const Duration(seconds: 10));

        setState(() {
          _admins.removeWhere((admin) => admin['id'] == id);
          _isSaving = false;
        });

        _showSnackBar('Admin deleted!', Colors.green);
      } catch (e) {
        setState(() {
          _errorMessage = _handleErrorMessage(e);
          _isSaving = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Super Admin - Manage Admins',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Add Admin Form
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: Colors.green,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter full name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email (@mak.ac.ug)',
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: Colors.green,
                      ),
                      hintText: 'admin@mak.ac.ug',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter email';
                      }
                      if (!value.endsWith('@mak.ac.ug')) {
                        return 'Must be a Makerere University email (@mak.ac.ug)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _employeeIdController,
                    decoration: InputDecoration(
                      labelText: 'Employee ID',
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(
                        Icons.badge_outlined,
                        color: Colors.green,
                      ),
                      hintText: 'MAK-EMP-001',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter employee ID';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(
                        Icons.phone_outlined,
                        color: Colors.green,
                      ),
                      hintText: '+256 XXX XXX XXX',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: _isSaving ? null : _addAdmin,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'CREATE ADMIN ACCOUNT',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.red[50],
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.red),
                    onPressed: () => setState(() => _errorMessage = null),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  )
                : _admins.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No admins created yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use the form above to create your first admin',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchAdmins,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(15),
                      itemCount: _admins.length,
                      itemBuilder: (context, index) {
                        final admin = _admins[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey[300]!),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey[100]!,
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green[100],
                              child: Text(
                                (index + 1).toString(),
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              admin['full_name'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            subtitle: Text(
                              admin['email'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            trailing: SizedBox(
                              width: 100,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.password_outlined,
                                      color: Colors.orange,
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () => _resetPassword(
                                            admin['id'].toString(),
                                            admin['email'],
                                            admin['full_name'],
                                          ),
                                    tooltip: 'Reset Password',
                                  ),
                                  const SizedBox(width: 5),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () => _deleteAdmin(
                                            admin['id'].toString(),
                                            admin['full_name'],
                                          ),
                                    tooltip: 'Delete Admin',
                                  ),
                                ],
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow(
                                      Icons.badge_outlined,
                                      'Employee ID',
                                      admin['employee_id'],
                                    ),
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      Icons.phone_outlined,
                                      'Phone',
                                      admin['phone'],
                                    ),
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      Icons.calendar_today_outlined,
                                      'Created',
                                      admin['created_at'] != null
                                          ? _formatDate(
                                              admin['created_at'].toString(),
                                            )
                                          : 'N/A',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      Icons.admin_panel_settings_outlined,
                                      'Role',
                                      admin['role'] == 'makerere_admin'
                                          ? 'Makerere Admin'
                                          : admin['role'],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  String _formatDate(String dateTime) {
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateTime.split('T')[0];
    }
  }
}
