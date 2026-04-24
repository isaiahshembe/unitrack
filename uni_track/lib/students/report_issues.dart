import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ReportIssuePage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const ReportIssuePage({super.key, this.userData});

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  final _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;

  bool _isLoadingCategories = true;
  String? _categoriesError;

  List<File> _attachments = [];
  List<String> _attachmentNames = [];
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _savedIssues = [];
  bool _isLoadingIssues = false;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchSavedIssues();
    _requestPermissions();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Permission.photos.request();
      await Permission.camera.request();
      await Permission.storage.request();
    }
  }

  Future<void> _fetchCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final response = await _supabase
          .from('issue_categories')
          .select('*, issue_priorities(*)')
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(response);
          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _fetchSavedIssues() async {
    print('=== _fetchSavedIssues START ===');
    setState(() => _isLoadingIssues = true);

    try {
      final studentId = widget.userData?['id'];
      print('Student ID from userData: $studentId');
      print('Student ID type: ${studentId?.runtimeType}');
      print('Full userData: ${widget.userData}');

      if (studentId == null) {
        print('ERROR: No student ID in userData');
        setState(() => _isLoadingIssues = false);
        return;
      }

      // Try the simplest possible query
      print('Executing Supabase query...');
      final response = await _supabase
          .from('issues')
          .select('*')
          .eq('student_id', studentId)
          .order('created_at', ascending: false)
          .limit(5);

      print('Query successful!');
      print('Response type: ${response.runtimeType}');
      print('Response length: ${response.length}');

      if (response.isNotEmpty) {
        print('First issue title: ${response[0]['title']}');
        print('First issue keys: ${response[0].keys}');
      } else {
        print('Response is EMPTY - no issues found for this student');
      }

      if (mounted) {
        setState(() {
          _savedIssues = List<Map<String, dynamic>>.from(response);
          _isLoadingIssues = false;
        });
        print('State updated with ${_savedIssues.length} issues');
      }
    } catch (e, stackTrace) {
      print('=== ERROR ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isLoadingIssues = false);
      }
    }
    print('=== _fetchSavedIssues END ===');
  }

  Future<void> _pickImages() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.photos.request();
        if (!status.isGranted) {
          _showSnackBar(
            'Permission denied. Cannot access gallery.',
            Colors.red,
          );
          return;
        }
      }
      final List<XFile>? images = await _picker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
        setState(() {
          for (var image in images) {
            _attachments.add(File(image.path));
            _attachmentNames.add(image.path.split('/').last);
          }
        });
        _showSnackBar('${images.length} image(s) added', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error picking images: $e', Colors.red);
    }
  }

  Future<void> _takePhoto() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          _showSnackBar('Camera permission denied', Colors.red);
          return;
        }
      }
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        setState(() {
          _attachments.add(File(photo.path));
          _attachmentNames.add(photo.path.split('/').last);
        });
        _showSnackBar('Photo added', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error taking photo: $e', Colors.red);
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
      _attachmentNames.removeAt(index);
    });
  }

  Widget _buildImagePreview(File file, int index) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Stack(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.grey[400],
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: () => _removeAttachment(index),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(String? priorityName) {
    switch (priorityName?.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getPriorityName(int? priorityId) {
    switch (priorityId) {
      case 1:
        return 'Low';
      case 2:
        return 'High';
      case 3:
        return 'Medium';
      case 4:
        return 'Critical';
      default:
        return 'N/A';
    }
  }

  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      _showSnackBar('Please select an issue category', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final selectedCategory = _categories.firstWhere(
        (c) => c['id'].toString() == _selectedCategoryId,
      );
      final priority = selectedCategory['issue_priorities'];

      final issueData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'category_id': int.parse(_selectedCategoryId!),
        'priority_id': priority['id'],
        'student_id': widget.userData?['id'],
        'student_email': widget.userData?['email'],
        'student_name': widget.userData?['full_name'],
        'student_phone': widget.userData?['phone'],
        'college_id': widget.userData?['college_id'],
        'course_id': widget.userData?['course_id'],
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('issues').insert(issueData);

      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnackBar('Issue reported successfully!', Colors.green);
        _titleController.clear();
        _descriptionController.clear();
        _locationController.clear();
        _selectedCategoryId = null;
        _attachments.clear();
        _attachmentNames.clear();
        _fetchSavedIssues();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
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
          'Report New Issue',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Issue Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Issue Title *',
                  hintText: 'Brief summary of the issue',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.green, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please enter issue title'
                    : null,
              ),
              const SizedBox(height: 16),

              // Category
              const Text(
                'Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              if (_isLoadingCategories)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_categoriesError != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _categoriesError!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _fetchCategories,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (_categories.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.warning, color: Colors.orange),
                      SizedBox(height: 8),
                      Text('No categories available.'),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      value: _selectedCategoryId,
                      hint: const Text('Select issue category'),
                      isExpanded: true,
                      items: _categories.map((category) {
                        final priority = category['issue_priorities'];
                        final color = _getPriorityColor(priority?['name']);
                        return DropdownMenuItem(
                          value: category['id'].toString(),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  category['name'],
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  priority?['name'] ?? 'N/A',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() {
                        _selectedCategoryId = v;
                      }),
                      validator: (v) =>
                          v == null ? 'Please select a category' : null,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Location
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location *',
                  hintText: 'e.g., COCIS Building, Room 301',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.green, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please enter location'
                    : null,
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Provide detailed information about the issue',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.green, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'Please enter issue description';
                  if (v.length < 20)
                    return 'Please provide more details (minimum 20 characters)';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submitIssue,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'SUBMIT ISSUE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 30),

              // ========== SAVED ISSUES ==========
              if (_isLoadingIssues)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_savedIssues.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'Your Recent Issues',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _fetchSavedIssues,
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._savedIssues.map((issue) => _buildSavedIssueCard(issue)),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedIssueCard(Map<String, dynamic> issue) {
    final priorityId = issue['priority_id'];
    final priorityName = _getPriorityName(priorityId);
    final priorityColor = _getPriorityColor(priorityName);
    final status = issue['status']?.toString() ?? 'pending';
    final statusColor = status == 'resolved'
        ? Colors.green
        : status == 'pending'
        ? Colors.orange
        : Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 50,
            decoration: BoxDecoration(
              color: priorityColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue['title']?.toString() ?? 'Untitled',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      priorityName,
                      style: TextStyle(
                        fontSize: 11,
                        color: priorityColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue['location']?.toString() ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ],
      ),
    );
  }
}
