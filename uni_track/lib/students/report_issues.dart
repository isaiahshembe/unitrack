import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:html' as html;

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

  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;

  // File attachment variables
  String? _selectedFileName;
  Uint8List? _selectedFileData;
  String? _selectedFileType;
  int? _selectedFileSize;
  bool _isUploading = false;

  bool _isLoadingCategories = true;
  String? _categoriesError;

  bool _isSubmitting = false;

  List<Map<String, dynamic>> _savedIssues = [];
  bool _isLoadingIssues = false;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchSavedIssues();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
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
      if (mounted) {
        setState(() {
          _isLoadingCategories = false;
          _categoriesError = e.toString();
        });
      }
    }
  }

  Future<void> _fetchSavedIssues() async {
    setState(() => _isLoadingIssues = true);

    try {
      final studentId = widget.userData?['id'];

      if (studentId == null) {
        setState(() => _isLoadingIssues = false);
        return;
      }

      final response = await _supabase
          .from('issues')
          .select('*')
          .eq('student_id', studentId)
          .order('created_at', ascending: false)
          .limit(5);

      if (mounted) {
        setState(() {
          _savedIssues = List<Map<String, dynamic>>.from(response);
          _isLoadingIssues = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingIssues = false);
      }
    }
  }

  // Web file picker
  void _pickFileWeb() {
    final html.FileUploadInputElement uploadInput =
        html.FileUploadInputElement();
    uploadInput.accept = '*/*';
    uploadInput.multiple = false;

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        _selectedFileName = file.name;
        _selectedFileType = file.type;
        _selectedFileSize = file.size;

        if (_selectedFileSize! > 10 * 1024 * 1024) {
          _showSnackBar('File size must be less than 10MB', Colors.red);
          return;
        }

        final fileReader = html.FileReader();
        fileReader.onLoadEnd.listen((event) {
          setState(() {
            _selectedFileData = fileReader.result as Uint8List?;
          });
          _showSnackBar('File selected: ${file.name}', Colors.green);
        });
        fileReader.readAsArrayBuffer(file);
      }
    });

    uploadInput.click();
  }

  // Mobile file picker
  Future<void> _pickFileMobile() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _showSnackBar('Storage permission required', Colors.red);
          return;
        }
      }

      final ImagePicker picker = ImagePicker();

      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select File Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Document'),
                onTap: () => Navigator.pop(context, 'document'),
              ),
            ],
          ),
        ),
      );

      if (result == null) return;

      XFile? pickedFile;

      if (result == 'camera') {
        pickedFile = await picker.pickImage(source: ImageSource.camera);
      } else if (result == 'gallery') {
        pickedFile = await picker.pickImage(source: ImageSource.gallery);
      }

      if (pickedFile != null) {
        _selectedFileName = pickedFile.name;
        _selectedFileType = pickedFile.mimeType;

        final bytes = await pickedFile.readAsBytes();
        _selectedFileData = bytes;
        _selectedFileSize = bytes.length;

        if (_selectedFileSize! > 10 * 1024 * 1024) {
          _showSnackBar('File size must be less than 10MB', Colors.red);
          return;
        }

        setState(() {});
        _showSnackBar('File selected: ${pickedFile.name}', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error picking file: $e', Colors.red);
    }
  }

  // Unified file picker
  Future<void> _pickFile() async {
    try {
      if (html.window != null) {
        _pickFileWeb();
        return;
      }
    } catch (e) {}

    await _pickFileMobile();
  }

  // Upload file to Supabase Storage
  Future<Map<String, dynamic>?> _uploadFile() async {
    if (_selectedFileData == null) return null;

    setState(() => _isUploading = true);

    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String sanitizedName = _selectedFileName!
          .replaceAll(RegExp(r'[^\w\s.-]'), '')
          .replaceAll(' ', '_');
      final String fileName = '$timestamp-$sanitizedName';
      final String filePath = fileName;

      await _supabase.storage.from('issue_attachments').uploadBinary(
            filePath,
            _selectedFileData!,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );

      final String publicUrl =
          _supabase.storage.from('issue_attachments').getPublicUrl(filePath);

      String fileExtension = 'unknown';
      if (_selectedFileName!.contains('.')) {
        fileExtension = _selectedFileName!.split('.').last.toLowerCase();
      }

      setState(() => _isUploading = false);

      return {
        'url': publicUrl,
        'name': _selectedFileName,
        'type': fileExtension,
        'size': _selectedFileSize,
      };
    } catch (e) {
      setState(() => _isUploading = false);
      _showSnackBar('Upload failed: ${e.toString()}', Colors.red);
      return null;
    }
  }

  void _removeFile() {
    setState(() {
      _selectedFileName = null;
      _selectedFileData = null;
      _selectedFileType = null;
      _selectedFileSize = null;
    });
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

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String? fileType) {
    if (fileType == null) return Icons.attach_file;
    final ext = fileType.toLowerCase();
    if (ext.contains('pdf')) return Icons.picture_as_pdf;
    if (ext.contains('jpg') ||
        ext.contains('jpeg') ||
        ext.contains('png') ||
        ext.contains('gif')) {
      return Icons.image;
    }
    if (ext.contains('doc')) return Icons.description;
    if (ext.contains('xls')) return Icons.table_chart;
    if (ext.contains('ppt')) return Icons.slideshow;
    if (ext.contains('mp4') || ext.contains('mov')) return Icons.video_file;
    if (ext.contains('mp3') || ext.contains('wav')) return Icons.audio_file;
    if (ext.contains('zip') || ext.contains('rar')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      _showSnackBar('Please select an issue category', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? attachmentUrl;
      String? attachmentName;
      String? attachmentType;
      int? attachmentSize;

      if (_selectedFileData != null) {
        final uploadResult = await _uploadFile();
        if (uploadResult != null) {
          attachmentUrl = uploadResult['url'];
          attachmentName = uploadResult['name'];
          attachmentType = uploadResult['type'];
          attachmentSize = uploadResult['size'];
        }
      }

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
        'attachment_url': attachmentUrl,
        'attachment_name': attachmentName,
        'attachment_type': attachmentType,
        'attachment_size': attachmentSize,
      };

      await _supabase.from('issues').insert(issueData);

      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnackBar('Issue reported successfully!', Colors.green);
        _titleController.clear();
        _descriptionController.clear();
        _locationController.clear();
        _selectedCategoryId = null;
        _removeFile();
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Report New Issue',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
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
                      borderRadius: BorderRadius.circular(12)),
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
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              if (_isLoadingCategories)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.green)),
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
                      Text(_categoriesError!,
                          style: TextStyle(color: Colors.red[700])),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _fetchCategories,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
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
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                    color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  category['name'],
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  priority?['name'] ?? 'N/A',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: color),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
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
                      borderRadius: BorderRadius.circular(12)),
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
                      borderRadius: BorderRadius.circular(12)),
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
              const SizedBox(height: 16),

              // File Attachment Section
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.attachment, color: Colors.green[600], size: 20),
                  const SizedBox(width: 8),
                  const Text('Attachment (Optional)',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),

              if (_selectedFileName == null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose File'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(_getFileIcon(_selectedFileType),
                          color: Colors.green[600], size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedFileName!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(_formatFileSize(_selectedFileSize),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: _removeFile,
                        tooltip: 'Remove file',
                      ),
                    ],
                  ),
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed:
                      (_isSubmitting || _isUploading) ? null : _submitIssue,
                  child: (_isSubmitting || _isUploading)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'SUBMIT ISSUE',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 30),

              // Saved Issues Section
              if (_isLoadingIssues)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.green)),
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
                          color: Colors.black87),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _fetchSavedIssues,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.green),
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
    final hasAttachment = issue['attachment_url'] != null &&
        issue['attachment_url'].toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey[100]!,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
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
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          priorityName,
                          style: TextStyle(
                              fontSize: 11,
                              color: priorityColor,
                              fontWeight: FontWeight.w500),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: statusColor),
                          ),
                        ),
                        if (hasAttachment)
                          Icon(Icons.attachment,
                              size: 12, color: Colors.blue[600]),
                        Text(
                          issue['location']?.toString() ?? '',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
            ],
          ),
        ],
      ),
    );
  }
}
