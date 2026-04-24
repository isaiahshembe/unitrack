import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddCollege extends StatefulWidget {
  const AddCollege({super.key});

  @override
  State<AddCollege> createState() => _AddCollegeState();
}

class _AddCollegeState extends State<AddCollege> {
  final _formKey = GlobalKey<FormState>();
  final _collegeNameController = TextEditingController();
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _colleges = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  final _editController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchColleges();
  }

  @override
  void dispose() {
    _collegeNameController.dispose();
    _editController.dispose();
    super.dispose();
  }

  Future<void> _fetchColleges() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('colleges')
          .select()
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      setState(() {
        _colleges = List<Map<String, dynamic>>.from(response);
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
        return 'Table "colleges" does not exist. Please create it in Supabase.';
      }
      return 'Database error: ${error.message}';
    }
    return 'Error: $error';
  }

  Future<void> _addCollege() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('colleges')
          .insert({
            'name': _collegeNameController.text.trim(),
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .timeout(const Duration(seconds: 10));

      setState(() {
        _colleges.insert(0, Map<String, dynamic>.from(response[0]));
        _collegeNameController.clear();
        _isSaving = false;
      });

      _showSnackBar('College added successfully!', Colors.green);
    } catch (e) {
      setState(() {
        _errorMessage = _handleErrorMessage(e);
        _isSaving = false;
      });
    }
  }

  Future<void> _updateCollege(String id, String oldName) async {
    _editController.text = oldName;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Edit College',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: _editController,
          decoration: InputDecoration(
            labelText: 'College Name',
            labelStyle: TextStyle(color: Colors.grey[600]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.green, width: 2),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () =>
                Navigator.pop(context, _editController.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      setState(() {
        _isSaving = true;
        _errorMessage = null;
      });

      try {
        await _supabase
            .from('colleges')
            .update({'name': newName})
            .eq('id', id)
            .timeout(const Duration(seconds: 10));

        setState(() {
          final index = _colleges.indexWhere((college) => college['id'] == id);
          if (index != -1) {
            _colleges[index]['name'] = newName;
          }
          _isSaving = false;
        });

        _showSnackBar('College updated successfully!', Colors.green);
      } catch (e) {
        setState(() {
          _errorMessage = _handleErrorMessage(e);
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteCollege(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete College',
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
        await _supabase
            .from('colleges')
            .delete()
            .eq('id', id)
            .timeout(const Duration(seconds: 10));

        setState(() {
          _colleges.removeWhere((college) => college['id'] == id);
          _isSaving = false;
        });

        _showSnackBar('College deleted successfully!', Colors.green);
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
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Manage Colleges',
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
          // Add College Form
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
                  // Text Field
                  TextFormField(
                    controller: _collegeNameController,
                    decoration: InputDecoration(
                      labelText: 'College Name',
                      labelStyle: TextStyle(color: Colors.grey[600]),
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
                        return 'Please enter college name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  // ADD Button - Full Width
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
                      onPressed: _isSaving ? null : _addCollege,
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
                              'ADD COLLEGE',
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

          // Error Message
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

          // Colleges List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  )
                : _colleges.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No colleges added yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the ADD COLLEGE button to create your first college',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchColleges,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(15),
                      itemCount: _colleges.length,
                      itemBuilder: (context, index) {
                        final college = _colleges[index];
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
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
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
                              college['name'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            trailing: SizedBox(
                              width: 100,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: Colors.grey,
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () => _updateCollege(
                                            college['id'].toString(),
                                            college['name'],
                                          ),
                                  ),
                                  const SizedBox(width: 5),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () => _deleteCollege(
                                            college['id'].toString(),
                                            college['name'],
                                          ),
                                  ),
                                ],
                              ),
                            ),
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
}
