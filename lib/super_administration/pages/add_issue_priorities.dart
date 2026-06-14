import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddIssuePriorities extends StatefulWidget {
  const AddIssuePriorities({super.key});

  @override
  State<AddIssuePriorities> createState() => _AddIssuePrioritiesState();
}

class _AddIssuePrioritiesState extends State<AddIssuePriorities> {
  final _formKey = GlobalKey<FormState>();
  final _priorityNameController = TextEditingController();
  final _daysController = TextEditingController();
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _priorities = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  
  String? _editingId;
  final _editPriorityNameController = TextEditingController();
  final _editDaysController = TextEditingController();

  // Predefined colors for priorities
  final Map<String, Color> _priorityColors = {
    'Low': Colors.green,
    'Medium': Colors.orange,
    'High': Colors.deepOrange,
    'Critical': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    _fetchPriorities();
  }

  @override
  void dispose() {
    _priorityNameController.dispose();
    _daysController.dispose();
    _editPriorityNameController.dispose();
    _editDaysController.dispose();
    super.dispose();
  }

  Future<void> _fetchPriorities() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('issue_priorities')
          .select()
          .order('days_to_resolve', ascending: true)
          .timeout(const Duration(seconds: 10));

      setState(() {
        _priorities = List<Map<String, dynamic>>.from(response);
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
        return 'Table "issue_priorities" does not exist. Please create it in Supabase.';
      }
      return 'Database error: ${error.message}';
    }
    return 'Error: $error';
  }

  Future<void> _addPriority() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final priorityName = _priorityNameController.text.trim();
      final daysToResolve = int.parse(_daysController.text.trim());
      
      final response = await _supabase
          .from('issue_priorities')
          .insert({
            'name': priorityName,
            'days_to_resolve': daysToResolve,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .timeout(const Duration(seconds: 10));

      setState(() {
        _priorities.insert(0, Map<String, dynamic>.from(response[0]));
        _priorityNameController.clear();
        _daysController.clear();
        _isSaving = false;
      });

      _showSnackBar('Priority added successfully!', Colors.green);
    } catch (e) {
      setState(() {
        _errorMessage = _handleErrorMessage(e);
        _isSaving = false;
      });
    }
  }

  Future<void> _updatePriority(String id, String oldName, int oldDays) async {
    _editPriorityNameController.text = oldName;
    _editDaysController.text = oldDays.toString();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Edit Priority',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _editPriorityNameController,
              decoration: InputDecoration(
                labelText: 'Priority Name',
                labelStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.green, width: 2),
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _editDaysController,
              decoration: InputDecoration(
                labelText: 'Days to Resolve',
                labelStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.green, width: 2),
                ),
                suffixText: 'days',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      final newName = _editPriorityNameController.text.trim();
      final newDays = int.tryParse(_editDaysController.text.trim());
      
      if (newName.isNotEmpty && newDays != null && (newName != oldName || newDays != oldDays)) {
        setState(() {
          _isSaving = true;
          _errorMessage = null;
        });

        try {
          final updates = <String, dynamic>{};
          if (newName != oldName) updates['name'] = newName;
          if (newDays != oldDays) updates['days_to_resolve'] = newDays;
          
          await _supabase
              .from('issue_priorities')
              .update(updates)
              .eq('id', id)
              .timeout(const Duration(seconds: 10));

          setState(() {
            final index = _priorities.indexWhere((priority) => priority['id'] == id);
            if (index != -1) {
              if (newName != oldName) _priorities[index]['name'] = newName;
              if (newDays != oldDays) _priorities[index]['days_to_resolve'] = newDays;
            }
            _isSaving = false;
          });

          _showSnackBar('Priority updated successfully!', Colors.green);
        } catch (e) {
          setState(() {
            _errorMessage = _handleErrorMessage(e);
            _isSaving = false;
          });
        }
      }
    }
  }

  Future<void> _deletePriority(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete Priority',
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
            .from('issue_priorities')
            .delete()
            .eq('id', id)
            .timeout(const Duration(seconds: 10));

        setState(() {
          _priorities.removeWhere((priority) => priority['id'] == id);
          _isSaving = false;
        });

        _showSnackBar('Priority deleted successfully!', Colors.green);
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

  String _getDaysText(int days) {
    if (days == 1) return '1 day';
    return '$days days';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Manage Issue Priorities',
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
          // Add Priority Form
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
                  // Priority Name Field
                  TextFormField(
                    controller: _priorityNameController,
                    decoration: InputDecoration(
                      labelText: 'Priority Name',
                      hintText: 'e.g., Low, Medium, High, Critical',
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
                        return 'Please enter priority name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  
                  // Days to Resolve Field
                  TextFormField(
                    controller: _daysController,
                    decoration: InputDecoration(
                      labelText: 'Days to Resolve',
                      hintText: 'Number of days to resolve issues with this priority',
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
                      suffixText: 'days',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter days to resolve';
                      }
                      final days = int.tryParse(value);
                      if (days == null || days < 1) {
                        return 'Please enter a valid number of days (minimum 1)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  
                  // Add Button
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
                      onPressed: _isSaving ? null : _addPriority,
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
                              'ADD PRIORITY',
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

          // Info Box
          Container(
            margin: const EdgeInsets.all(15),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Issues will automatically escalate to the next priority level if not resolved within the specified days',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
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

          // Priorities List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  )
                : _priorities.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.priority_high_outlined,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Priorities Added',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add priorities like Low, Medium, High, Critical',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchPriorities,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(15),
                          itemCount: _priorities.length,
                          itemBuilder: (context, index) {
                            final priority = _priorities[index];
                            final priorityName = priority['name'];
                            final daysToResolve = priority['days_to_resolve'];
                            final color = _priorityColors[priorityName] ?? Colors.grey;
                            
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
                                  backgroundColor: color.withOpacity(0.2),
                                  child: Icon(
                                    _getPriorityIcon(priorityName),
                                    color: color,
                                  ),
                                ),
                                title: Text(
                                  priorityName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                                subtitle: Text(
                                  'Resolution time: ${_getDaysText(daysToResolve)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Days Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: color.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        '$daysToResolve days',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: Colors.grey,
                                      ),
                                      onPressed: _isSaving
                                          ? null
                                          : () => _updatePriority(
                                              priority['id'].toString(),
                                              priorityName,
                                              daysToResolve,
                                            ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: _isSaving
                                          ? null
                                          : () => _deletePriority(
                                              priority['id'].toString(),
                                              priorityName,
                                            ),
                                    ),
                                  ],
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

  IconData _getPriorityIcon(String priorityName) {
    switch (priorityName.toLowerCase()) {
      case 'low':
        return Icons.arrow_downward;
      case 'medium':
        return Icons.remove;
      case 'high':
        return Icons.arrow_upward;
      case 'critical':
        return Icons.warning;
      default:
        return Icons.priority_high;
    }
  }
}