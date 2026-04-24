import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/administration/admin_loginpage.dart';

class AdminProfilepage extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminProfilepage({super.key, required this.adminData});

  @override
  State<AdminProfilepage> createState() => _AdminProfilepageState();
}

class _AdminProfilepageState extends State<AdminProfilepage> {
  final _supabase = Supabase.instance.client;

  // Assigned Office
  Map<String, dynamic>? _assignedOffice;
  bool _isLoadingOffice = true;

  // Phone update
  bool _isEditingPhone = false;
  final _phoneController = TextEditingController();
  bool _isSavingPhone = false;

  // Password change
  final _passwordFormKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isChangingPassword = false;
  bool _isSavingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _phoneController.text = widget.adminData['phone'] ?? '';
    _fetchAssignedOffice();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _fetchAssignedOffice() async {
    try {
      final response = await _supabase
          .from('office_assignments')
          .select('*, offices(*, colleges(name), departments(name))')
          .eq('admin_id', widget.adminData['id'])
          .maybeSingle();

      if (mounted) {
        setState(() {
          _assignedOffice = response;
          _isLoadingOffice = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingOffice = false);
    }
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _supabase.auth.signOut();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (c) => const AdminLoginpage()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePhone() async {
    if (_phoneController.text.trim().isEmpty) {
      _showSnackBar('Please enter phone number', Colors.orange);
      return;
    }
    setState(() => _isSavingPhone = true);
    try {
      await _supabase
          .from('admins')
          .update({
            'phone': _phoneController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.adminData['id']);
      setState(() {
        _isEditingPhone = false;
        _isSavingPhone = false;
        widget.adminData['phone'] = _phoneController.text.trim();
      });
      _showSnackBar('Phone updated successfully!', Colors.green);
    } catch (e) {
      setState(() => _isSavingPhone = false);
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _isSavingPassword = true);
    try {
      final email = widget.adminData['email'];
      try {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: _currentPasswordController.text.trim(),
        );
      } catch (e) {
        setState(() => _isSavingPassword = false);
        _showSnackBar('Current password is incorrect', Colors.red);
        return;
      }
      await _supabase.auth.updateUser(
        UserAttributes(password: _newPasswordController.text.trim()),
      );
      await _supabase
          .from('admins')
          .update({
            'password': _newPasswordController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.adminData['id']);
      setState(() {
        _isSavingPassword = false;
        _isChangingPassword = false;
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
      _showSnackBar('Password changed successfully!', Colors.green);
    } catch (e) {
      setState(() => _isSavingPassword = false);
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final office = _assignedOffice?['offices'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile Picture
            Center(
              child: Container(
                height: 100,
                width: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green[100]!,
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.green,
                  child: const Icon(
                    Icons.admin_panel_settings,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.adminData['full_name'] ?? 'N/A',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Makerere University Admin',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),

            // Assigned Office Card
            if (_isLoadingOffice)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (office != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.business, color: Colors.blue[700], size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Assigned Office',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildOfficeDetail(
                      Icons.apartment,
                      'Office',
                      office['name']?.toString() ?? 'N/A',
                    ),
                    _buildOfficeDetail(
                      Icons.layers,
                      'Level',
                      office['level']?.toString() ?? 'N/A',
                    ),
                    _buildOfficeDetail(
                      Icons.location_on,
                      'Building',
                      office['building']?.toString() ?? 'N/A',
                    ),
                    _buildOfficeDetail(
                      Icons.meeting_room,
                      'Room',
                      office['room_number']?.toString() ?? 'N/A',
                    ),
                    if (office['colleges'] != null)
                      _buildOfficeDetail(
                        Icons.school,
                        'College',
                        office['colleges']['name']?.toString() ?? 'N/A',
                      ),
                    if (office['departments'] != null)
                      _buildOfficeDetail(
                        Icons.account_tree,
                        'Department',
                        office['departments']['name']?.toString() ?? 'N/A',
                      ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700]),
                    const SizedBox(width: 10),
                    Text(
                      'No office assigned yet',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Info Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [BoxShadow(color: Colors.grey[50]!, blurRadius: 10)],
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    Icons.email,
                    'Email',
                    widget.adminData['email'] ?? 'N/A',
                    Colors.red,
                  ),
                  const Divider(height: 1),
                  _buildInfoRow(
                    Icons.badge,
                    'Employee ID',
                    widget.adminData['employee_id'] ?? 'N/A',
                    Colors.blue,
                  ),
                  const Divider(height: 1),
                  _buildInfoRow(
                    Icons.admin_panel_settings,
                    'Role',
                    'Makerere Admin',
                    Colors.purple,
                  ),
                  const Divider(height: 1),
                  // Phone - Editable
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.phone,
                            color: Colors.green,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _isEditingPhone
                              ? TextFormField(
                                  controller: _phoneController,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone Number',
                                    border: InputBorder.none,
                                  ),
                                  keyboardType: TextInputType.phone,
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Phone',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      widget.adminData['phone']?.isNotEmpty ==
                                              true
                                          ? widget.adminData['phone']
                                          : 'Not provided',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isEditingPhone ? Icons.check : Icons.edit,
                            color: Colors.green,
                          ),
                          onPressed: () => _isEditingPhone
                              ? _updatePhone()
                              : setState(() => _isEditingPhone = true),
                        ),
                        if (_isEditingPhone)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => setState(() {
                              _isEditingPhone = false;
                              _phoneController.text =
                                  widget.adminData['phone'] ?? '';
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Change Password Card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [BoxShadow(color: Colors.grey[50]!, blurRadius: 10)],
              ),
              child: ExpansionTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock, color: Colors.orange, size: 24),
                ),
                title: const Text(
                  'Change Password',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                initiallyExpanded: _isChangingPassword,
                onExpansionChanged: (expanded) =>
                    setState(() => _isChangingPassword = expanded),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _passwordFormKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _currentPasswordController,
                            obscureText: _obscureCurrent,
                            decoration: InputDecoration(
                              labelText: 'Current Password',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureCurrent
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _obscureCurrent = !_obscureCurrent,
                                ),
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Enter current password'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: _obscureNew,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureNew
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () =>
                                    setState(() => _obscureNew = !_obscureNew),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty)
                                return 'Enter new password';
                              if (v.length < 6) return 'At least 6 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirm,
                            decoration: InputDecoration(
                              labelText: 'Confirm New Password',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty)
                                return 'Confirm new password';
                              if (v != _newPasswordController.text)
                                return 'Passwords do not match';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSavingPassword
                                  ? null
                                  : _changePassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isSavingPassword
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'UPDATE PASSWORD',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'LOGOUT',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildOfficeDetail(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
