import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddOffice extends StatefulWidget {
  const AddOffice({super.key});

  @override
  State<AddOffice> createState() => _AddOfficeState();
}

class _AddOfficeState extends State<AddOffice> {
  final _formKey = GlobalKey<FormState>();
  final _officeNameController = TextEditingController();
  final _buildingController = TextEditingController();
  final _roomNumberController = TextEditingController();
  final _descriptionController = TextEditingController();

  final _supabase = Supabase.instance.client;

  // Office Levels
  final List<String> _officeLevels = [
    'Top Level',
    'College Level',
    'Department Level',
  ];
  String? _selectedLevel;

  // For College Level
  List<Map<String, dynamic>> _colleges = [];
  String? _selectedCollegeId;
  String? _selectedCollegeName;

  // For Department Level
  List<Map<String, dynamic>> _departments = [];
  String? _selectedDepartmentId;
  String? _selectedDepartmentName;

  // Lists for displaying offices
  List<Map<String, dynamic>> _offices = [];
  List<Map<String, dynamic>> _topLevelOffices = [];
  List<Map<String, dynamic>> _collegeOffices = [];
  List<Map<String, dynamic>> _departmentOffices = [];

  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _selectedTab = 'All';

  // For editing
  String? _editingId;
  final _editOfficeNameController = TextEditingController();
  final _editBuildingController = TextEditingController();
  final _editRoomNumberController = TextEditingController();
  final _editDescriptionController = TextEditingController();
  String? _editSelectedLevel;
  String? _editSelectedCollegeId;
  String? _editSelectedDepartmentId;

  @override
  void initState() {
    super.initState();
    _fetchColleges();
    _fetchOffices();
  }

  @override
  void dispose() {
    _officeNameController.dispose();
    _buildingController.dispose();
    _roomNumberController.dispose();
    _descriptionController.dispose();
    _editOfficeNameController.dispose();
    _editBuildingController.dispose();
    _editRoomNumberController.dispose();
    _editDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _fetchColleges() async {
    try {
      final response = await _supabase
          .from('colleges')
          .select()
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _colleges = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {}
  }

  Future<void> _fetchDepartments(String collegeId) async {
    try {
      final response = await _supabase
          .from('departments')
          .select()
          .eq('college_id', collegeId)
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {}
  }

  Future<void> _fetchOffices() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('offices')
          .select('*, colleges(name), departments(name)')
          .order('name', ascending: true);

      final offices = List<Map<String, dynamic>>.from(response);

      if (mounted) {
        setState(() {
          _offices = offices;
          _topLevelOffices = offices
              .where((office) => office['level'] == 'Top Level')
              .toList();
          _collegeOffices = offices
              .where((office) => office['level'] == 'College Level')
              .toList();
          _departmentOffices = offices
              .where((office) => office['level'] == 'Department Level')
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _handleErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  String _handleErrorMessage(dynamic error) {
    if (error is PostgrestException) {
      if (error.code == '42P01') {
        return 'Table "offices" does not exist. Please create it in Supabase.';
      }
      return 'Database error: ${error.message}';
    }
    return 'Error: $error';
  }

  Future<void> _addOffice() async {
    if (_selectedLevel == null) {
      _showSnackBar('Please select office level', Colors.orange);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_selectedLevel == 'College Level' && _selectedCollegeId == null) {
      _showSnackBar('Please select a college', Colors.orange);
      return;
    }

    if (_selectedLevel == 'Department Level' && _selectedDepartmentId == null) {
      _showSnackBar('Please select a department', Colors.orange);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final Map<String, dynamic> officeData = {
        'name': _officeNameController.text.trim(),
        'level': _selectedLevel,
        'building': _buildingController.text.trim(),
        'room_number': _roomNumberController.text.trim(),
        'description': _descriptionController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      if (_selectedLevel == 'College Level' ||
          _selectedLevel == 'Department Level') {
        officeData['college_id'] = int.parse(_selectedCollegeId!);
      }

      if (_selectedLevel == 'Department Level') {
        officeData['department_id'] = int.parse(_selectedDepartmentId!);
      }

      final response = await _supabase
          .from('offices')
          .insert(officeData)
          .select('*, colleges(name), departments(name)');

      if (mounted) {
        setState(() {
          _offices.insert(0, Map<String, dynamic>.from(response[0]));
          _clearForm();
          _isSaving = false;
        });

        _categorizeOffices();
        _showSnackBar('Office added successfully!', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _handleErrorMessage(e);
          _isSaving = false;
        });
      }
    }
  }

  void _clearForm() {
    _officeNameController.clear();
    _buildingController.clear();
    _roomNumberController.clear();
    _descriptionController.clear();
    _selectedLevel = null;
    _selectedCollegeId = null;
    _selectedCollegeName = null;
    _selectedDepartmentId = null;
    _selectedDepartmentName = null;
    _departments = [];
  }

  void _categorizeOffices() {
    if (!mounted) return;
    setState(() {
      _topLevelOffices =
          _offices.where((office) => office['level'] == 'Top Level').toList();
      _collegeOffices = _offices
          .where((office) => office['level'] == 'College Level')
          .toList();
      _departmentOffices = _offices
          .where((office) => office['level'] == 'Department Level')
          .toList();
    });
  }

  Future<void> _updateOffice(Map<String, dynamic> office) async {
    _editOfficeNameController.text = office['name'];
    _editBuildingController.text = office['building'] ?? '';
    _editRoomNumberController.text = office['room_number'] ?? '';
    _editDescriptionController.text = office['description'] ?? '';
    _editSelectedLevel = office['level'];
    _editSelectedCollegeId = office['college_id']?.toString();
    _editSelectedDepartmentId = office['department_id']?.toString();

    if (_editSelectedCollegeId != null && _editSelectedCollegeId != 'null') {
      await _fetchDepartments(_editSelectedCollegeId!);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Edit Office'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _editOfficeNameController,
                    decoration: InputDecoration(
                      labelText: 'Office Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Office Level',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    value: _editSelectedLevel,
                    items: _officeLevels.map((level) {
                      return DropdownMenuItem<String>(
                        value: level,
                        child: Text(level),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        _editSelectedLevel = value;
                        if (value != 'Department Level') {
                          _editSelectedDepartmentId = null;
                        }
                      });
                    },
                  ),
                  if (_editSelectedLevel == 'College Level' ||
                      _editSelectedLevel == 'Department Level')
                    const SizedBox(height: 12),
                  if (_editSelectedLevel == 'College Level' ||
                      _editSelectedLevel == 'Department Level')
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'College',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      value: _editSelectedCollegeId,
                      items: _colleges.map((college) {
                        return DropdownMenuItem<String>(
                          value: college['id'].toString(),
                          child: Text(college['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          _editSelectedCollegeId = value;
                          _editSelectedDepartmentId = null;
                          if (value != null) {
                            _fetchDepartments(value);
                          }
                        });
                      },
                    ),
                  if (_editSelectedLevel == 'Department Level')
                    const SizedBox(height: 12),
                  if (_editSelectedLevel == 'Department Level')
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      value: _editSelectedDepartmentId,
                      items: _departments.map((dept) {
                        return DropdownMenuItem<String>(
                          value: dept['id'].toString(),
                          child: Text(dept['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          _editSelectedDepartmentId = value;
                        });
                      },
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _editBuildingController,
                    decoration: InputDecoration(
                      labelText: 'Building',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _editRoomNumberController,
                    decoration: InputDecoration(
                      labelText: 'Room Number',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _editDescriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      setState(() => _isSaving = true);

      try {
        final Map<String, dynamic> updates = {
          'name': _editOfficeNameController.text.trim(),
          'level': _editSelectedLevel,
          'building': _editBuildingController.text.trim(),
          'room_number': _editRoomNumberController.text.trim(),
          'description': _editDescriptionController.text.trim(),
        };

        if (_editSelectedLevel == 'College Level' ||
            _editSelectedLevel == 'Department Level') {
          if (_editSelectedCollegeId != null &&
              _editSelectedCollegeId != 'null') {
            updates['college_id'] = int.parse(_editSelectedCollegeId!);
          }
        } else {
          updates['college_id'] = null;
        }

        if (_editSelectedLevel == 'Department Level') {
          if (_editSelectedDepartmentId != null &&
              _editSelectedDepartmentId != 'null') {
            updates['department_id'] = int.parse(_editSelectedDepartmentId!);
          }
        } else {
          updates['department_id'] = null;
        }

        await _supabase.from('offices').update(updates).eq('id', office['id']);

        await _fetchOffices();
        if (mounted) setState(() => _isSaving = false);
        _showSnackBar('Office updated successfully!', Colors.green);
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = _handleErrorMessage(e);
            _isSaving = false;
          });
        }
      }
    }
  }

  Future<void> _deleteOffice(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Office'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
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
        await _supabase.from('offices').delete().eq('id', id);
        await _fetchOffices();
        if (mounted) setState(() => _isSaving = false);
        _showSnackBar('Office deleted successfully!', Colors.green);
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = _handleErrorMessage(e);
            _isSaving = false;
          });
        }
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildOfficeCard(Map<String, dynamic> office, int index) {
    final level = office['level'];
    Color levelColor;
    IconData levelIcon;

    switch (level) {
      case 'Top Level':
        levelColor = Colors.purple;
        levelIcon = Icons.star;
        break;
      case 'College Level':
        levelColor = Colors.blue;
        levelIcon = Icons.business;
        break;
      case 'Department Level':
        levelColor = Colors.green;
        levelIcon = Icons.category;
        break;
      default:
        levelColor = Colors.grey;
        levelIcon = Icons.location_city;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: levelColor.withOpacity(0.1),
          child: Icon(levelIcon, color: levelColor, size: 24),
        ),
        title: Text(
          office['name'],
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${office['building'] ?? 'No building'} • Room ${office['room_number'] ?? 'N/A'}',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: levelColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                level!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: levelColor,
                ),
              ),
            ),
            IconButton(
              icon:
                  const Icon(Icons.edit_outlined, color: Colors.grey, size: 20),
              onPressed: _isSaving ? null : () => _updateOffice(office),
            ),
            IconButton(
              icon:
                  const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: _isSaving
                  ? null
                  : () =>
                      _deleteOffice(office['id'].toString(), office['name']),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(Icons.category, 'Level', office['level']),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.location_on, 'Building',
                    office['building'] ?? 'Not specified'),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.meeting_room, 'Room Number',
                    office['room_number'] ?? 'Not specified'),
                if (office['colleges'] != null) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(
                      Icons.business, 'College', office['colleges']['name']),
                ],
                if (office['departments'] != null) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.account_tree, 'Department',
                      office['departments']['name']),
                ],
                if (office['description'] != null &&
                    office['description'].isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(
                      Icons.description, 'Description', office['description']),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[500]),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Manage Offices',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Add Office Form
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey[200]!,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.add_business,
                                      color: Colors.green),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Add New Office',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _officeNameController,
                              decoration: InputDecoration(
                                labelText: 'Office Name',
                                hintText: 'e.g., Vice Chancellor\'s Office',
                                prefixIcon: const Icon(Icons.business_center),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? 'Required'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Office Level',
                                prefixIcon: const Icon(Icons.flag),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                              ),
                              value: _selectedLevel,
                              hint: const Text('Select level'),
                              items: _officeLevels.map((level) {
                                return DropdownMenuItem<String>(
                                  value: level,
                                  child: Row(
                                    children: [
                                      Icon(
                                        level == 'Top Level'
                                            ? Icons.star
                                            : level == 'College Level'
                                                ? Icons.business
                                                : Icons.category,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(level),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedLevel = value;
                                  _selectedCollegeId = null;
                                  _selectedDepartmentId = null;
                                  _departments = [];
                                });
                              },
                              validator: (value) =>
                                  value == null ? 'Select level' : null,
                            ),
                            if (_selectedLevel == 'College Level' ||
                                _selectedLevel == 'Department Level')
                              const SizedBox(height: 12),
                            if (_selectedLevel == 'College Level' ||
                                _selectedLevel == 'Department Level')
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'College',
                                  prefixIcon: const Icon(Icons.school),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  isDense: true,
                                ),
                                value: _selectedCollegeId,
                                hint: const Text('Select college'),
                                items: _colleges.map((college) {
                                  return DropdownMenuItem<String>(
                                    value: college['id'].toString(),
                                    child: Text(college['name']),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedCollegeId = value;
                                    _selectedDepartmentId = null;
                                    if (value != null) _fetchDepartments(value);
                                  });
                                },
                                validator: (value) =>
                                    value == null ? 'Select college' : null,
                              ),
                            if (_selectedLevel == 'Department Level')
                              const SizedBox(height: 12),
                            if (_selectedLevel == 'Department Level')
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'Department',
                                  prefixIcon: const Icon(Icons.account_tree),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  isDense: true,
                                ),
                                value: _selectedDepartmentId,
                                hint: const Text('Select department'),
                                items: _departments.map((dept) {
                                  return DropdownMenuItem<String>(
                                    value: dept['id'].toString(),
                                    child: Text(dept['name']),
                                  );
                                }).toList(),
                                onChanged: (value) => setState(
                                    () => _selectedDepartmentId = value),
                                validator: (value) =>
                                    value == null ? 'Select department' : null,
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _buildingController,
                                    decoration: InputDecoration(
                                      labelText: 'Building',
                                      prefixIcon: const Icon(Icons.location_on),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      isDense: true,
                                    ),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                            ? 'Required'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _roomNumberController,
                                    decoration: InputDecoration(
                                      labelText: 'Room Number',
                                      prefixIcon:
                                          const Icon(Icons.meeting_room),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      isDense: true,
                                    ),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                            ? 'Required'
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _descriptionController,
                              decoration: InputDecoration(
                                labelText: 'Description (Optional)',
                                prefixIcon: const Icon(Icons.description),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _isSaving ? null : _addOffice,
                                child: _isSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'ADD OFFICE',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_errorMessage!)),
                          GestureDetector(
                            onTap: () => setState(() => _errorMessage = null),
                            child: const Icon(Icons.close, size: 20),
                          ),
                        ],
                      ),
                    ),

                  // Tabs
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTab('All', _offices.length, Colors.grey),
                          const SizedBox(width: 8),
                          _buildTab('Top Level', _topLevelOffices.length,
                              Colors.purple),
                          const SizedBox(width: 8),
                          _buildTab('College Level', _collegeOffices.length,
                              Colors.blue),
                          const SizedBox(width: 8),
                          _buildTab('Department Level',
                              _departmentOffices.length, Colors.green),
                        ],
                      ),
                    ),
                  ),

                  // Office List
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: Colors.green)),
                        )
                      : _getCurrentOffices().isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(Icons.business_outlined,
                                      size: 80, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No Offices Added',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap the button above to add your first office',
                                    style: TextStyle(
                                        fontSize: 14, color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchOffices,
                              child: ListView.builder(
                                shrinkWrap: true,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                itemCount: _getCurrentOffices().length,
                                itemBuilder: (context, index) {
                                  return _buildOfficeCard(
                                      _getCurrentOffices()[index], index);
                                },
                              ),
                            ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTab(String title, int count, Color color) {
    final isSelected = _selectedTab == title;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = title),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getCurrentOffices() {
    switch (_selectedTab) {
      case 'Top Level':
        return _topLevelOffices;
      case 'College Level':
        return _collegeOffices;
      case 'Department Level':
        return _departmentOffices;
      default:
        return _offices;
    }
  }
}
