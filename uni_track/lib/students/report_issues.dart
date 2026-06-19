import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uni_track/services/mobile_data_service.dart';

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
  final _data = MobileDataService();

  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;
  Map<String, dynamic>? _lastAiResult;

  Map<String, dynamic>? _aiSuggestion;
  bool _isAiLoading = false;
  String? _aiError;
  Timer? _aiDebounceTimer;

  List<Map<String, dynamic>> _offices = [];
  String? _selectedOfficeId;

  double? _gpsLatitude;
  double? _gpsLongitude;
  bool _isGettingLocation = false;

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
    _fetchOffices();
    _fetchSavedIssues();
    _titleController.addListener(_onTextChanged);
    _descriptionController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTextChanged);
    _descriptionController.removeListener(_onTextChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _aiDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final response = await _data.getCategories();
      if (mounted) {
        setState(() {
          _categories = response;
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

  Future<void> _fetchOffices() async {
    try {
      final offices = await _data.getOfficesList();
      if (mounted) {
        setState(() => _offices = offices);
      }
    } catch (_) {}
  }

  Future<void> _fetchSavedIssues() async {
    setState(() => _isLoadingIssues = true);

    try {
      final studentId = widget.userData?['id'];

      if (studentId == null) {
        setState(() => _isLoadingIssues = false);
        return;
      }

      final response = await _data.getComplaints(
        studentId: studentId.toString(),
        limit: 5,
      );
      final complaints =
          List<Map<String, dynamic>>.from(response['complaints'] ?? []);

      if (mounted) {
        setState(() {
          _savedIssues = complaints;
          _isLoadingIssues = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingIssues = false);
      }
    }
  }

  Future<void> _pickFileMobile() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _showSnackBar('Storage permission required', Colors.red);
          return;
        }
      }

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

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      final locationPermission = await Geolocator.requestPermission();
      if (locationPermission == LocationPermission.denied ||
          locationPermission == LocationPermission.deniedForever) {
        _showSnackBar('Location permission denied', Colors.orange);
        setState(() => _isGettingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _gpsLatitude = position.latitude;
        _gpsLongitude = position.longitude;
        _isGettingLocation = false;
        if (_locationController.text.trim().isEmpty) {
          _locationController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        }
      });
      _showSnackBar('Location obtained', Colors.green);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGettingLocation = false);
      _showSnackBar('Could not get location: $e', Colors.red);
    }
  }

  void _onTextChanged() {
    _aiDebounceTimer?.cancel();
    _aiDebounceTimer =
        Timer(const Duration(milliseconds: 800), _triggerAiSuggestion);
  }

  Future<void> _triggerAiSuggestion() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.length < 5 || description.length < 20) return;

    setState(() {
      _isAiLoading = true;
      _aiError = null;
      _aiSuggestion = null;
    });

    try {
      final result = await _data.suggestCategoryAndOffice(
        title: title,
        description: description,
      );
      if (!mounted) return;
      setState(() {
        _aiSuggestion = result;
        _isAiLoading = false;
        final suggestedCategoryId = result['categoryId'];
        if (suggestedCategoryId != null) {
          _selectedCategoryId = suggestedCategoryId.toString();
        }
        final suggestedOfficeId = result['officeId'];
        if (suggestedOfficeId != null) {
          _selectedOfficeId = suggestedOfficeId.toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAiLoading = false;
        _aiError = e.toString();
      });
    }
  }

  Future<Map<String, dynamic>?> _submitIssueToMobileData({
    required String title,
    required String description,
    required int categoryId,
    int? officeId,
    String? location,
    double? gpsLatitude,
    double? gpsLongitude,
    String? attachmentUrl,
    String? attachmentName,
    String? attachmentType,
    int? attachmentSize,
  }) async {
    final response = await _data.createComplaint(
      studentId: widget.userData?['id']?.toString() ?? '',
      title: title,
      description: description,
      categoryId: categoryId,
      officeId: officeId,
      location: location,
      gpsLatitude: gpsLatitude,
      gpsLongitude: gpsLongitude,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
      attachmentType: attachmentType,
      attachmentSize: attachmentSize,
    );
    return response;
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

  String _getPriorityName(dynamic priorityId) {
    final id = priorityId is int ? priorityId : int.tryParse('$priorityId');
    switch (id) {
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
    if (_selectedOfficeId == null) {
      _showSnackBar('Please select an office', Colors.orange);
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

      final webComplaint = await _submitIssueToMobileData(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        categoryId: int.parse(_selectedCategoryId!),
        officeId: int.tryParse(_selectedOfficeId!),
        location: _locationController.text.trim(),
        gpsLatitude: _gpsLatitude,
        gpsLongitude: _gpsLongitude,
        attachmentUrl: attachmentUrl,
        attachmentName: attachmentName,
        attachmentType: attachmentType,
        attachmentSize: attachmentSize,
      );

      _lastAiResult = webComplaint;

      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnackBar('Issue reported successfully!', Colors.green);
        _titleController.clear();
        _descriptionController.clear();
        _locationController.clear();
        _selectedCategoryId = null;
        _selectedOfficeId = null;
        _gpsLatitude = null;
        _gpsLongitude = null;
        _aiSuggestion = null;
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

              // AI Suggestion Section
              _buildAiSuggestionSection(),
              const SizedBox(height: 16),

              // Category
              Row(
                children: [
                  const Text(
                    'Category',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                  ),
                  if (_aiSuggestion != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 11, color: Colors.indigo[700]),
                          const SizedBox(width: 3),
                          Text('AI',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo[700])),
                        ],
                      ),
                    ),
                  ],
                ],
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
                        final priority = category['priority'];
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

              // Office
              Row(
                children: [
                  const Text(
                    'Office',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                  ),
                  if (_aiSuggestion != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 11, color: Colors.indigo[700]),
                          const SizedBox(width: 3),
                          Text('AI',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo[700])),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
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
                    value: _selectedOfficeId,
                    hint: const Text('Select office'),
                    isExpanded: true,
                    items: _offices.map((office) {
                      return DropdownMenuItem(
                        value: office['id'].toString(),
                        child: Text(
                          office['name'] ?? 'Unnamed',
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedOfficeId = v),
                    validator: (v) =>
                        v == null ? 'Please select an office' : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Location with GPS
              Row(
                children: [
                  const Text(
                    'Location *',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 32,
                    child: TextButton.icon(
                      onPressed:
                          _isGettingLocation ? null : _getCurrentLocation,
                      icon: _isGettingLocation
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 16),
                      label: Text(
                        _isGettingLocation ? 'Locating...' : 'Use GPS',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: Colors.indigo,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location description or coordinates',
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
                  suffixIcon: _gpsLatitude != null
                      ? Tooltip(
                          message:
                              'Lat: ${_gpsLatitude!.toStringAsFixed(4)}, Lng: ${_gpsLongitude!.toStringAsFixed(4)}',
                          child: Icon(Icons.location_on,
                              color: Colors.green[600], size: 20),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please enter location'
                    : null,
              ),
              if (_gpsLatitude != null) ...[
                const SizedBox(height: 4),
                Text(
                  '📍 ${_gpsLatitude!.toStringAsFixed(4)}, ${_gpsLongitude!.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 11, color: Colors.green[700]),
                ),
              ],
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

              if (_lastAiResult != null) ...[
                _buildAiResultCard(_lastAiResult!),
                const SizedBox(height: 30),
              ],

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

  Widget _buildAiSuggestionSection() {
    if (_isAiLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'AI is analyzing your issue...',
              style: TextStyle(fontSize: 13, color: Colors.blue[800]),
            ),
          ],
        ),
      );
    }

    if (_aiError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.orange[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI suggestion unavailable. Please select a category manually.',
                style: TextStyle(fontSize: 12, color: Colors.orange[800]),
              ),
            ),
          ],
        ),
      );
    }

    if (_aiSuggestion == null) return const SizedBox.shrink();

    final confidence =
        ((_aiSuggestion!['confidence'] ?? 0) * 100).toStringAsFixed(0);
    final categoryName = _aiSuggestion!['categoryName']?.toString() ?? 'N/A';
    final officeName = _aiSuggestion!['officeName']?.toString() ?? 'Unassigned';
    final reasoning = _aiSuggestion!['reasoning']?.toString();
    final matchedKeywords =
        (_aiSuggestion!['matchedKeywords'] as List?)?.cast<String>() ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.indigo[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.indigo[700], size: 18),
              const SizedBox(width: 8),
              Text(
                'AI Suggestion',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[800],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.indigo[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$confidence% confidence',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSuggestionRow(
              Icons.category, 'Category', categoryName, Colors.indigo),
          _buildSuggestionRow(
              Icons.business, 'Office', officeName, Colors.indigo),
          if (reasoning != null && reasoning.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reasoning,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.indigo[700],
                  fontStyle: FontStyle.italic),
            ),
          ],
          if (matchedKeywords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: matchedKeywords.take(6).map((keyword) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.indigo[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    keyword,
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.indigo[700],
                        fontWeight: FontWeight.w500),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionRow(
      IconData icon, String label, String value, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color[700],
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildAiResultCard(Map<String, dynamic> result) {
    final complaint = result['complaint'] as Map<String, dynamic>? ?? {};
    final classification = result['classification'] as Map<String, dynamic>? ??
        complaint['classification'] as Map<String, dynamic>? ??
        complaint['nlpResults']?['classification'] as Map<String, dynamic>?;
    final rag = result['rag'] as Map<String, dynamic>? ??
        complaint['rag'] as Map<String, dynamic>? ??
        complaint['nlpResults']?['rag'] as Map<String, dynamic>?;
    final similar = List<Map<String, dynamic>>.from(
      result['similarComplaints'] ?? complaint['similarComplaints'] ?? [],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.green[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI Routing & NLP Result',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAiMetric(
              'Tracking Code', complaint['trackingCode']?.toString() ?? 'N/A'),
          _buildAiMetric(
              'Category', complaint['category']?['name']?.toString() ?? 'N/A'),
          _buildAiMetric('Assigned Office',
              complaint['office']?['name']?.toString() ?? 'Unassigned'),
          _buildAiMetric(
              'Priority', complaint['priority']?.toString() ?? 'N/A'),
          if (classification != null) ...[
            _buildAiMetric('NLP Confidence',
                '${((classification['confidence'] ?? 0) * 100).toStringAsFixed(1)}%'),
            _buildAiMetric(
                'NLP Method', classification['method']?.toString() ?? 'N/A'),
          ],
          if (rag != null) ...[
            _buildAiMetric('RAG Confidence',
                '${((rag['confidence'] ?? 0) * 100).toStringAsFixed(1)}%'),
            _buildAiMetric(
                'Routed Office',
                rag['officeName']?.toString() ??
                    complaint['office']?['name']?.toString() ??
                    'N/A'),
            Text(
              rag['reasoning']?.toString() ??
                  'No routing explanation available',
              style: TextStyle(fontSize: 12, color: Colors.green[900]),
            ),
          ],
          if (similar.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Similar historical complaints: ${similar.length}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[800]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedIssueCard(Map<String, dynamic> issue) {
    dynamic priority = issue['priority'];
    final rawPriorityName =
        priority is Map ? priority['name']?.toString() : null;
    final priorityName =
        rawPriorityName ?? _getPriorityName(issue['priority_id']);
    final priorityColor = _getPriorityColor(priorityName);
    final status = issue['status']?.toString() ?? 'pending';
    final statusColor = status.toUpperCase() == 'RESOLVED'
        ? Colors.green
        : status.toUpperCase() == 'PENDING' || status.toUpperCase() == 'OPEN'
            ? Colors.orange
            : Colors.blue;
    final attachments = issue['attachments'] is List
        ? List.from(issue['attachments'])
        : <Map<String, dynamic>>[];
    final hasAttachment = attachments.isNotEmpty;

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
