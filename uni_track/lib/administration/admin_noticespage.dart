import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class AdminNoticesPage extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminNoticesPage({super.key, required this.adminData});

  @override
  State<AdminNoticesPage> createState() => _AdminNoticesPageState();
}

class _AdminNoticesPageState extends State<AdminNoticesPage> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  List<Map<String, dynamic>> _notices = [];
  List<Map<String, dynamic>> _colleges = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _courses = [];

  String _selectedTargetType = 'public';
  String? _selectedCollegeId;
  String? _selectedDepartmentId;
  String? _selectedCourseId;

  // File attachment variables
  String? _selectedFileName;
  Uint8List? _selectedFileData;
  String? _selectedFileType;
  int? _selectedFileSize;
  bool _isUploading = false;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _showForm = false;
  String? _errorMessage;

  final List<Map<String, dynamic>> _targetTypes = [
    {
      'type': 'public',
      'label': 'Public',
      'icon': Icons.public,
      'color': Colors.green
    },
    {
      'type': 'college',
      'label': 'College',
      'icon': Icons.business,
      'color': Colors.purple
    },
    {
      'type': 'department',
      'label': 'Department',
      'icon': Icons.category,
      'color': Colors.orange
    },
    {
      'type': 'course',
      'label': 'Course',
      'icon': Icons.menu_book,
      'color': Colors.teal
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchNotices();
    _fetchColleges();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchNotices() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('notices')
          .select('*, colleges(name), departments(name), courses(name)')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _notices = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchColleges() async {
    try {
      final response = await _supabase.from('colleges').select().order('name');
      if (mounted)
        setState(() => _colleges = List<Map<String, dynamic>>.from(response));
    } catch (e) {}
  }

  Future<void> _fetchDepartments(String collegeId) async {
    try {
      final response = await _supabase
          .from('departments')
          .select()
          .eq('college_id', collegeId)
          .order('name');
      if (mounted)
        setState(
            () => _departments = List<Map<String, dynamic>>.from(response));
    } catch (e) {}
  }

  Future<void> _fetchCourses(String departmentId) async {
    try {
      final response = await _supabase
          .from('courses')
          .select()
          .eq('department_id', departmentId)
          .order('name');
      if (mounted)
        setState(() => _courses = List<Map<String, dynamic>>.from(response));
    } catch (e) {}
  }

  Future<void> _pickFileMobile() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _showSnackBar(
              'Storage permission is required to select files', Colors.red);
          return;
        }
      }

      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Source'),
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

      if (result == 'document') {
        final pickedFile = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );

        if (pickedFile == null || pickedFile.files.isEmpty) return;

        final file = pickedFile.files.first;
        if (file.bytes == null) {
          _showSnackBar('Unable to read selected file', Colors.red);
          return;
        }

        _selectedFileName = file.name;
        _selectedFileType = file.extension;
        _selectedFileData = file.bytes;
        _selectedFileSize = file.size;

        if (_selectedFileSize! > 10 * 1024 * 1024) {
          _showSnackBar('File size must be less than 10MB', Colors.red);
          return;
        }

        setState(() {});
        _showSnackBar('File selected: ${file.name}', Colors.green);
        return;
      }

      final ImagePicker picker = ImagePicker();
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

  Future<void> _pickFile() async {
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

      await _supabase.storage.from('notice_attachments').uploadBinary(
            filePath,
            _selectedFileData!,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );

      final String publicUrl =
          _supabase.storage.from('notice_attachments').getPublicUrl(filePath);

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

  // Remove selected file
  void _removeFile() {
    setState(() {
      _selectedFileName = null;
      _selectedFileData = null;
      _selectedFileType = null;
      _selectedFileSize = null;
    });
  }

  Future<void> _sendNotice() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTargetType == 'college' && _selectedCollegeId == null) {
      _showSnackBar('Please select a college', Colors.orange);
      return;
    }
    if (_selectedTargetType == 'department' && _selectedDepartmentId == null) {
      _showSnackBar('Please select a department', Colors.orange);
      return;
    }
    if (_selectedTargetType == 'course' && _selectedCourseId == null) {
      _showSnackBar('Please select a course', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

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
        } else {
          setState(() => _isSaving = false);
          return;
        }
      }

      final noticeData = {
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'target_type': _selectedTargetType,
        'admin_id': widget.adminData['id'],
        'admin_name': widget.adminData['full_name'],
        'created_at': DateTime.now().toIso8601String(),
        'attachment_url': attachmentUrl,
        'attachment_name': attachmentName,
        'attachment_type': attachmentType,
        'attachment_size': attachmentSize,
      };

      if (_selectedTargetType == 'college') {
        noticeData['college_id'] = int.parse(_selectedCollegeId!);
      } else if (_selectedTargetType == 'department') {
        noticeData['department_id'] = int.parse(_selectedDepartmentId!);
        noticeData['college_id'] = int.parse(_selectedCollegeId!);
      } else if (_selectedTargetType == 'course') {
        noticeData['course_id'] = int.parse(_selectedCourseId!);
        noticeData['department_id'] = int.parse(_selectedDepartmentId!);
        noticeData['college_id'] = int.parse(_selectedCollegeId!);
      }

      await _supabase.from('notices').insert(noticeData);
      _clearForm();
      await _fetchNotices();

      if (mounted) {
        setState(() {
          _isSaving = false;
          _showForm = false;
        });
        _showSnackBar('Notice sent successfully!', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  Future<void> _deleteNotice(
      String id, String title, String? attachmentUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Notice',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Delete "$title"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
          try {
            final uri = Uri.parse(attachmentUrl);
            final fileName = uri.pathSegments.last;
            await _supabase.storage
                .from('notice_attachments')
                .remove([fileName]);
          } catch (e) {
            debugPrint('Error deleting file: $e');
          }
        }
        await _supabase.from('notices').delete().eq('id', id);
        _fetchNotices();
        _showSnackBar('Notice deleted successfully', Colors.green);
      } catch (e) {
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  void _clearForm() {
    _titleController.clear();
    _messageController.clear();
    setState(() {
      _selectedTargetType = 'public';
      _selectedCollegeId = null;
      _selectedDepartmentId = null;
      _selectedCourseId = null;
      _departments = [];
      _courses = [];
      _selectedFileName = null;
      _selectedFileData = null;
      _selectedFileType = null;
      _selectedFileSize = null;
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 2)),
    );
  }

  // ==================== IN-APP FILE PREVIEW METHODS ====================

  /// Show in-app file preview (images only, others open in new tab)
  void _showInAppPreview(String url, String fileName, String? fileType) {
    if (url.isEmpty) {
      _showSnackBar('No file to preview', Colors.orange);
      return;
    }

    final fileExt = fileName.toLowerCase().split('.').last;
    final isImage =
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(fileExt);

    if (isImage) {
      _showImagePreviewDialog(url, fileName, fileExt);
    } else {
      // For non-image files, open in new tab or download
      _showFileActionDialog(url, fileName, fileExt, fileType);
    }
  }

  /// Show full-screen image preview with zoom
  void _showImagePreviewDialog(String url, String fileName, String fileExt) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.black,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  scaleEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    url,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            Text('Loading image...',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image,
                            size: 64, color: Colors.white54),
                        const SizedBox(height: 12),
                        Text('Failed to load image',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      fileName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show dialog for file actions (open/download)
  void _showFileActionDialog(
      String url, String fileName, String fileExt, String? fileType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getFileIcon(fileType), color: Colors.green[600], size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fileName,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Preview not available for .$fileExt files',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'You can open or download this file',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openInBrowser(url);
            },
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _downloadFile(url, fileName);
            },
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  /// Open file in browser (new tab)
  void _openInBrowser(String url) {
    _launchUrl(url);
  }

  /// Build text file preview (loads content from URL)
  Widget _buildTextPreview(String url) {
    return FutureBuilder<String>(
      future: _loadTextFile(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 12),
                Text('Failed to load text file',
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            snapshot.data ?? 'No content',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        );
      },
    );
  }

  /// Load text file content from URL
  Future<String> _loadTextFile(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.body;
      }
      return 'Failed to load file';
    } catch (e) {
      return 'Error loading file: $e';
    }
  }

  /// Download file
  void _downloadFile(String url, String fileName) {
    if (url.isEmpty) {
      _showSnackBar('No file to download', Colors.orange);
      return;
    }

    _launchUrl(url);
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {}
  }

  String _getTargetLabel(Map<String, dynamic> notice) {
    switch (notice['target_type']) {
      case 'public':
        return 'All Students';
      case 'college':
        return notice['colleges']?['name'] ?? 'College';
      case 'department':
        return notice['departments']?['name'] ?? 'Department';
      case 'course':
        return notice['courses']?['name'] ?? 'Course';
      default:
        return 'Unknown';
    }
  }

  IconData _getTargetIcon(String? type) {
    switch (type) {
      case 'public':
        return Icons.public;
      case 'college':
        return Icons.business;
      case 'department':
        return Icons.category;
      case 'course':
        return Icons.menu_book;
      default:
        return Icons.campaign;
    }
  }

  Color _getTargetColor(String? type) {
    switch (type) {
      case 'public':
        return Colors.green;
      case 'college':
        return Colors.purple;
      case 'department':
        return Colors.orange;
      case 'course':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date);
      final now = DateTime.now();
      final diff = now.difference(d);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${d.day}/${d.month}/${d.year}';
    } catch (e) {
      return date;
    }
  }

  String _formatFileSize(int bytes) {
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
        ext.contains('gif') ||
        ext.contains('webp')) {
      return Icons.image;
    }
    if (ext.contains('doc')) return Icons.description;
    if (ext.contains('xls')) return Icons.table_chart;
    if (ext.contains('ppt')) return Icons.slideshow;
    if (ext.contains('mp4')) return Icons.video_file;
    if (ext.contains('mp3') || ext.contains('wav')) return Icons.audio_file;
    if (ext.contains('txt') || ext.contains('md')) return Icons.text_snippet;
    if (ext.contains('zip') || ext.contains('rar')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _notices.length;
    final publicCount =
        _notices.where((n) => n['target_type'] == 'public').length;
    final collegeCount =
        _notices.where((n) => n['target_type'] == 'college').length;
    final departmentCount =
        _notices.where((n) => n['target_type'] == 'department').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Notices',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                fontSize: 20)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.green),
              onPressed: _fetchNotices),
          IconButton(
            icon: Icon(_showForm ? Icons.close : Icons.add_circle,
                color: Colors.green),
            onPressed: () => setState(() => _showForm = !_showForm),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Cards
          Container(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                    width: (MediaQuery.of(context).size.width - 52) / 2,
                    child: _buildStatCard('Total Notices',
                        totalCount.toString(), Colors.blue, Icons.campaign)),
                SizedBox(
                    width: (MediaQuery.of(context).size.width - 52) / 2,
                    child: _buildStatCard('Public', publicCount.toString(),
                        Colors.green, Icons.public)),
                SizedBox(
                    width: (MediaQuery.of(context).size.width - 52) / 2,
                    child: _buildStatCard('Colleges', collegeCount.toString(),
                        Colors.purple, Icons.business)),
                SizedBox(
                    width: (MediaQuery.of(context).size.width - 52) / 2,
                    child: _buildStatCard(
                        'Departments',
                        departmentCount.toString(),
                        Colors.orange,
                        Icons.category)),
              ],
            ),
          ),

          // Create Form
          if (_showForm)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.grey[100]!,
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.edit_note,
                              color: Colors.green[700], size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Text('Create New Notice',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                controller: _titleController,
                                decoration: InputDecoration(
                                  labelText: 'Notice Title',
                                  hintText: 'e.g., Exam Schedule Update',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  prefixIcon: const Icon(Icons.title,
                                      color: Colors.green),
                                ),
                                validator: (v) => v?.trim().isEmpty ?? true
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _messageController,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: 'Message',
                                  hintText: 'Write your notice content...',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  prefixIcon: const Padding(
                                    padding: EdgeInsets.only(bottom: 60),
                                    child: Icon(Icons.message,
                                        color: Colors.green),
                                  ),
                                ),
                                validator: (v) => v?.trim().isEmpty ?? true
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              const Text('Target Audience',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _targetTypes.map((t) {
                                  final isSelected =
                                      _selectedTargetType == t['type'];
                                  return ChoiceChip(
                                    avatar: Icon(t['icon'] as IconData,
                                        size: 16,
                                        color: isSelected
                                            ? t['color'] as Color
                                            : Colors.grey),
                                    label: Text(t['label'] as String),
                                    selected: isSelected,
                                    selectedColor:
                                        (t['color'] as Color).withOpacity(0.15),
                                    onSelected: (s) => setState(() {
                                      _selectedTargetType = t['type'] as String;
                                      if (t['type'] == 'public') {
                                        _selectedCollegeId = null;
                                        _selectedDepartmentId = null;
                                        _selectedCourseId = null;
                                      }
                                    }),
                                  );
                                }).toList(),
                              ),
                              if (_selectedTargetType != 'public') ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    labelText: 'Select College',
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    prefixIcon: const Icon(Icons.business,
                                        color: Colors.green),
                                    isDense: true,
                                  ),
                                  value: _selectedCollegeId,
                                  isExpanded: true,
                                  items: _colleges
                                      .map((c) => DropdownMenuItem(
                                          value: c['id'].toString(),
                                          child: Text(c['name'])))
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _selectedCollegeId = v;
                                      _selectedDepartmentId = null;
                                      _selectedCourseId = null;
                                    });
                                    if (v != null) _fetchDepartments(v);
                                  },
                                ),
                              ],
                              if (_selectedTargetType == 'department' ||
                                  _selectedTargetType == 'course') ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    labelText: 'Select Department',
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    prefixIcon: const Icon(Icons.category,
                                        color: Colors.green),
                                    isDense: true,
                                  ),
                                  value: _selectedDepartmentId,
                                  isExpanded: true,
                                  items: _departments
                                      .map((d) => DropdownMenuItem(
                                          value: d['id'].toString(),
                                          child: Text(d['name'])))
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _selectedDepartmentId = v;
                                      _selectedCourseId = null;
                                    });
                                    if (v != null) _fetchCourses(v);
                                  },
                                ),
                              ],
                              if (_selectedTargetType == 'course') ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    labelText: 'Select Course',
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    prefixIcon: const Icon(Icons.menu_book,
                                        color: Colors.green),
                                    isDense: true,
                                  ),
                                  value: _selectedCourseId,
                                  isExpanded: true,
                                  items: _courses
                                      .map((c) => DropdownMenuItem(
                                            value: c['id'].toString(),
                                            child: Text(
                                                '${c['name']} (${c['course_code']})'),
                                          ))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _selectedCourseId = v),
                                ),
                              ],

                              // File Attachment Section
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.attachment,
                                      color: Colors.green[600], size: 20),
                                  const SizedBox(width: 8),
                                  const Text('Attachment (Optional)',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
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
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: Colors.green[200]!),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(_getFileIcon(_selectedFileType),
                                          color: Colors.green[600], size: 32),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(_selectedFileName!,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w500)),
                                            const SizedBox(height: 4),
                                            Text(
                                                _formatFileSize(
                                                    _selectedFileSize ?? 0),
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600])),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close,
                                            color: Colors.red),
                                        onPressed: _removeFile,
                                        tooltip: 'Remove file',
                                      ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: (_isSaving || _isUploading)
                                      ? null
                                      : _sendNotice,
                                  icon: (_isSaving || _isUploading)
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(Icons.send),
                                  label: Text(
                                      _isUploading
                                          ? 'Uploading File...'
                                          : 'Send Notice',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Notices List
          if (!_showForm)
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.green)))
                  : _notices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    shape: BoxShape.circle),
                                child: Icon(Icons.campaign_outlined,
                                    size: 60, color: Colors.green[400]),
                              ),
                              const SizedBox(height: 16),
                              Text('No notices yet',
                                  style: TextStyle(
                                      fontSize: 20,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text('Tap + to create your first notice',
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchNotices,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _notices.length,
                            itemBuilder: (context, index) =>
                                _buildNoticeCard(_notices[index]),
                          ),
                        ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String count, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(count,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(label,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeCard(Map<String, dynamic> notice) {
    final targetType = notice['target_type'] as String?;
    final color = _getTargetColor(targetType);
    final icon = _getTargetIcon(targetType);
    final targetLabel = _getTargetLabel(notice);
    final message = notice['message'] ?? '';
    final isPublic = targetType == 'public';
    final hasAttachment = notice['attachment_url'] != null &&
        notice['attachment_url'].toString().isNotEmpty;
    final attachmentUrl = notice['attachment_url'] ?? '';
    final attachmentName = notice['attachment_name'] ?? 'Attachment';
    final attachmentType = notice['attachment_type'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.grey[100]!,
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showFullNotice(notice),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(notice['title'] ?? 'Untitled',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text(targetLabel,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: color)),
                              ),
                              if (isPublic)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: const Text('🌍 Public',
                                      style: TextStyle(fontSize: 10)),
                                ),
                              if (hasAttachment)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.attachment,
                                          size: 10, color: Colors.blue[700]),
                                      const SizedBox(width: 2),
                                      Text('Attachment',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue[700])),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () => _deleteNotice(
                          notice['id'].toString(),
                          notice['title'] ?? 'Untitled',
                          notice['attachment_url']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(message,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black87, height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                if (hasAttachment) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => _showInAppPreview(
                        attachmentUrl, attachmentName, attachmentType),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(_getFileIcon(attachmentType),
                              color: Colors.green[600], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(attachmentName,
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          const Icon(Icons.visibility,
                              size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.green[50],
                        child: Icon(Icons.person,
                            size: 14, color: Colors.green[600])),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(notice['admin_name'] ?? 'Admin',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500))),
                    Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(_formatDate(notice['created_at']),
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullNotice(Map<String, dynamic> notice) {
    final color = _getTargetColor(notice['target_type']);
    final hasAttachment = notice['attachment_url'] != null &&
        notice['attachment_url'].toString().isNotEmpty;
    final attachmentUrl = notice['attachment_url'] ?? '';
    final attachmentName = notice['attachment_name'] ?? 'Attachment';
    final attachmentType = notice['attachment_type'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(_getTargetLabel(notice),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
              const SizedBox(height: 8),
              Text(notice['title'] ?? '',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(notice['message'] ?? '',
                  style: const TextStyle(fontSize: 15, height: 1.6)),
              if (hasAttachment) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.attachment, color: Colors.green[600]),
                    const SizedBox(width: 8),
                    const Text('Attachment',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _showInAppPreview(
                        attachmentUrl, attachmentName, attachmentType);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(_getFileIcon(attachmentType),
                            color: Colors.green[600], size: 40),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(attachmentName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              if (notice['attachment_size'] != null)
                                Text(_formatFileSize(notice['attachment_size']),
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        const Icon(Icons.visibility, color: Colors.green),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.green[600]),
                  const SizedBox(width: 6),
                  Text('By: ${notice['admin_name'] ?? 'Admin'}',
                      style: TextStyle(color: Colors.grey[600])),
                  const Spacer(),
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text(_getFullDate(notice['created_at']),
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFullDate(String? date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date);
      return '${d.day}/${d.month}/${d.year} at ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return date;
    }
  }
}
