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
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      setState(() {
        _colleges = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error fetching colleges: $e');
    }
  }

  Future<void> _fetchDepartments(String collegeId) async {
    try {
      final response = await _supabase
          .from('departments')
          .select()
          .eq('college_id', collegeId)
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      setState(() {
        _departments = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
  }

  Future<void> _fetchOffices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('offices')
          .select('*, colleges(name), departments(name)')
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      final offices = List<Map<String, dynamic>>.from(response);

      // Categorize offices
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

    // Validate based on level
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

      // Add college_id if level is College or Department
      if (_selectedLevel == 'College Level' ||
          _selectedLevel == 'Department Level') {
        officeData['college_id'] = int.parse(_selectedCollegeId!);
      }

      // Add department_id if level is Department
      if (_selectedLevel == 'Department Level') {
        officeData['department_id'] = int.parse(_selectedDepartmentId!);
      }

      final response = await _supabase
          .from('offices')
          .insert(officeData)
          .select('*, colleges(name), departments(name)')
          .timeout(const Duration(seconds: 10));

      setState(() {
        _offices.insert(0, Map<String, dynamic>.from(response[0]));
        _clearForm();
        _isSaving = false;
      });

      _categorizeOffices();
      _showSnackBar('Office added successfully!', Colors.green);
    } catch (e) {
      setState(() {
        _errorMessage = _handleErrorMessage(e);
        _isSaving = false;
      });
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
    setState(() {
      _topLevelOffices = _offices
          .where((office) => office['level'] == 'Top Level')
          .toList();
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

    // Convert int to String? properly
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
            title: const Text(
              'Edit Office',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _editOfficeNameController,
                    decoration: const InputDecoration(
                      labelText: 'Office Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Office Level',
                      border: OutlineInputBorder(),
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
                  const SizedBox(height: 10),

                  if (_editSelectedLevel == 'College Level' ||
                      _editSelectedLevel == 'Department Level')
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'College',
                        border: OutlineInputBorder(),
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
                  const SizedBox(height: 10),

                  if (_editSelectedLevel == 'Department Level')
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(),
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
                  const SizedBox(height: 10),

                  TextField(
                    controller: _editBuildingController,
                    decoration: const InputDecoration(
                      labelText: 'Building',
                      hintText: 'e.g., Senate Building, COCIS Building',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _editRoomNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Room Number',
                      hintText: 'e.g., Room 301, Level 2',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _editDescriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Save',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final newName = _editOfficeNameController.text.trim();
      final newBuilding = _editBuildingController.text.trim();
      final newRoomNumber = _editRoomNumberController.text.trim();
      final newDescription = _editDescriptionController.text.trim();
      final newLevel = _editSelectedLevel;

      setState(() {
        _isSaving = true;
        _errorMessage = null;
      });

      try {
        final Map<String, dynamic> updates = {
          'name': newName,
          'level': newLevel,
          'building': newBuilding,
          'room_number': newRoomNumber,
          'description': newDescription,
        };

        if (newLevel == 'College Level' || newLevel == 'Department Level') {
          if (_editSelectedCollegeId != null &&
              _editSelectedCollegeId != 'null') {
            updates['college_id'] = int.parse(_editSelectedCollegeId!);
          }
        } else {
          updates['college_id'] = null;
        }

        if (newLevel == 'Department Level') {
          if (_editSelectedDepartmentId != null &&
              _editSelectedDepartmentId != 'null') {
            updates['department_id'] = int.parse(_editSelectedDepartmentId!);
          }
        } else {
          updates['department_id'] = null;
        }

        await _supabase
            .from('offices')
            .update(updates)
            .eq('id', office['id'])
            .timeout(const Duration(seconds: 10));

        await _fetchOffices();

        setState(() {
          _isSaving = false;
        });

        _showSnackBar('Office updated successfully!', Colors.green);
      } catch (e) {
        setState(() {
          _errorMessage = _handleErrorMessage(e);
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteOffice(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete Office',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
            .from('offices')
            .delete()
            .eq('id', id)
            .timeout(const Duration(seconds: 10));

        await _fetchOffices();

        setState(() {
          _isSaving = false;
        });

        _showSnackBar('Office deleted successfully!', Colors.green);
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
          backgroundColor: levelColor.withOpacity(0.2),
          child: Icon(levelIcon, color: levelColor),
        ),
        title: Text(
          office['name'],
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        subtitle: Text(
          '${office['building'] ?? 'No building'} • Room ${office['room_number'] ?? 'N/A'}',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: levelColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: levelColor.withOpacity(0.3)),
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
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.grey),
              onPressed: _isSaving ? null : () => _updateOffice(office),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isSaving
                  ? null
                  : () =>
                        _deleteOffice(office['id'].toString(), office['name']),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Office Details',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(Icons.category, 'Level', office['level']),
                      _buildDetailRow(
                        Icons.location_on,
                        'Building',
                        office['building'] ?? 'Not specified',
                      ),
                      _buildDetailRow(
                        Icons.meeting_room,
                        'Room Number',
                        office['room_number'] ?? 'Not specified',
                      ),
                      if (office['colleges'] != null)
                        _buildDetailRow(
                          Icons.business,
                          'College',
                          office['colleges']['name'],
                        ),
                      if (office['departments'] != null)
                        _buildDetailRow(
                          Icons.account_tree,
                          'Department',
                          office['departments']['name'],
                        ),
                      if (office['description'] != null &&
                          office['description'].isNotEmpty)
                        _buildDetailRow(
                          Icons.description,
                          'Description',
                          office['description'],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
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
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Manage Offices',
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
          // Add Office Form
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _officeNameController,
                      decoration: InputDecoration(
                        labelText: 'Office Name',
                        hintText:
                            'e.g., Vice Chancellor\'s Office, College Registrar Office',
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
                          return 'Please enter office name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),

                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Office Level',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: Colors.green,
                            width: 2,
                          ),
                        ),
                      ),
                      value: _selectedLevel,
                      hint: const Text('Select office level'),
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
                                color: level == 'Top Level'
                                    ? Colors.purple
                                    : level == 'College Level'
                                    ? Colors.blue
                                    : Colors.green,
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
                      validator: (value) {
                        if (value == null) {
                          return 'Please select office level';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),

                    if (_selectedLevel == 'College Level' ||
                        _selectedLevel == 'Department Level')
                      Column(
                        children: [
                          DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'College',
                              labelStyle: TextStyle(color: Colors.grey[600]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(
                                  color: Colors.green,
                                  width: 2,
                                ),
                              ),
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
                                if (value != null) {
                                  _fetchDepartments(value);
                                }
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return 'Please select a college';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 15),
                        ],
                      ),

                    if (_selectedLevel == 'Department Level')
                      Column(
                        children: [
                          DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Department',
                              labelStyle: TextStyle(color: Colors.grey[600]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(
                                  color: Colors.green,
                                  width: 2,
                                ),
                              ),
                            ),
                            value: _selectedDepartmentId,
                            hint: const Text('Select department'),
                            items: _departments.map((dept) {
                              return DropdownMenuItem<String>(
                                value: dept['id'].toString(),
                                child: Text(dept['name']),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedDepartmentId = value;
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return 'Please select a department';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 15),
                        ],
                      ),

                    TextFormField(
                      controller: _buildingController,
                      decoration: InputDecoration(
                        labelText: 'Building *',
                        hintText:
                            'e.g., Senate Building, COCIS Building, Main Hall',
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
                          return 'Please enter building name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: _roomNumberController,
                      decoration: InputDecoration(
                        labelText: 'Room Number *',
                        hintText: 'e.g., Room 301, Level 2, Office 5',
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
                          return 'Please enter room number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description (Optional)',
                        hintText: 'Additional information about this office',
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
                      maxLines: 2,
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
                        onPressed: _isSaving ? null : _addOffice,
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
                                'ADD OFFICE',
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

          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  _buildTab('All', _offices.length, Colors.grey),
                  const SizedBox(width: 8),
                  _buildTab(
                    'Top Level',
                    _topLevelOffices.length,
                    Colors.purple,
                  ),
                  const SizedBox(width: 8),
                  _buildTab(
                    'College Level',
                    _collegeOffices.length,
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildTab(
                    'Department Level',
                    _departmentOffices.length,
                    Colors.green,
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            flex: 5,
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  )
                : _getCurrentOffices().isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
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
                          'Add offices to start building the university structure',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchOffices,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(15),
                      itemCount: _getCurrentOffices().length,
                      itemBuilder: (context, index) {
                        return _buildOfficeCard(
                          _getCurrentOffices()[index],
                          index,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String title, int count, Color color) {
    final isSelected = _selectedTab == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = title;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey[700],
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
