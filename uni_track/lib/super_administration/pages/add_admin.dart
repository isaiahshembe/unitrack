import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          .order('created_at', ascending: false);

      setState(() {
        _admins = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching admins: $e';
        _isLoading = false;
      });
    }
  }

  String _generateRandomPassword() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%^&*';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        12, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
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
      // Create auth user
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

      // Save to database
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

      await _supabase.from('admins').insert(adminData);

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
      await _fetchAdmins();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isSaving = false;
      });
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _showPasswordDialog(
      String password, String adminName, String email) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Admin Created'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: $adminName',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text('Email: $email'),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  children: [
                    const Text('TEMPORARY PASSWORD:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SelectableText(
                      password,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Password'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: password));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                'Please save this password and share it with the admin.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(String id, String email, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('Reset password for "$name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSaving = true);
      final newPassword = _generateRandomPassword();

      try {
        await _supabase
            .from('admins')
            .update({'password': newPassword}).eq('id', id);
        setState(() => _isSaving = false);
        await _showPasswordDialog(newPassword, name, email);
        _showSnackBar('Password reset! New password generated.', Colors.green);
      } catch (e) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteAdmin(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Admin'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSaving = true);
      try {
        await _supabase.from('admins').delete().eq('id', id);
        setState(() {
          _admins.removeWhere((admin) => admin['id'] == id);
          _isSaving = false;
        });
        _showSnackBar('Admin deleted!', Colors.green);
      } catch (e) {
        setState(() {
          _errorMessage = 'Error deleting: $e';
          _isSaving = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Uni-Track - Manage Admins'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.green),
            onPressed: _fetchAdmins,
          ),
        ],
      ),
      body: Column(
        children: [
          // Form Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person, color: Colors.green),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email, color: Colors.green),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v == null || !v.contains('@')
                        ? 'Valid email required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _employeeIdController,
                    decoration: InputDecoration(
                      labelText: 'Employee ID',
                      prefixIcon: const Icon(Icons.badge, color: Colors.green),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: const Icon(Icons.phone, color: Colors.green),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSaving ? null : _addAdmin,
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('CREATE ADMIN',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ),

          // List Section
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.green))
                : _admins.isEmpty
                    ? const Center(child: Text('No admins created yet'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _admins.length,
                        itemBuilder: (context, index) {
                          final admin = _admins[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green[100],
                                child: Text('${index + 1}'),
                              ),
                              title: Text(admin['full_name']),
                              subtitle: Text(admin['email']),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.lock_reset,
                                        color: Colors.orange),
                                    onPressed: () => _resetPassword(
                                      admin['id'].toString(),
                                      admin['email'],
                                      admin['full_name'],
                                    ),
                                    tooltip: 'Reset Password',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _deleteAdmin(
                                      admin['id'].toString(),
                                      admin['full_name'],
                                    ),
                                    tooltip: 'Delete Admin',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
