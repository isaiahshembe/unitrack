import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

class NoticesPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const NoticesPage({super.key, this.userData});

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _notices = [];
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, bool> _downloadingFiles = {};

  @override
  void initState() {
    super.initState();
    _fetchNotices();
  }

  @override
  void didUpdateWidget(covariant NoticesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userData != widget.userData) {
      _fetchNotices();
    }
  }

  Future<void> _fetchNotices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final studentCollegeId = widget.userData?['college_id'];
      final studentCourseId = widget.userData?['course_id'];
      final studentDepartmentId = widget.userData?['department_id'];

      final response = await _supabase
          .from('notices')
          .select('*, colleges(name), departments(name), courses(name)')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      final filteredNotices = response.where((notice) {
        final targetType = notice['target_type']?.toString();
        final noticeCollegeId = notice['college_id'];
        final noticeDeptId = notice['department_id'];
        final noticeCourseId = notice['course_id'];

        if (targetType == 'public') return true;
        if (targetType == 'college') {
          return noticeCollegeId?.toString() == studentCollegeId?.toString();
        }
        if (targetType == 'department') {
          return noticeDeptId?.toString() == studentDepartmentId?.toString();
        }
        if (targetType == 'course') {
          return noticeCourseId?.toString() == studentCourseId?.toString();
        }
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _notices = List<Map<String, dynamic>>.from(filteredNotices);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load notices';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    if (_downloadingFiles[url] == true) {
      _showSnackBar('Download already in progress', Colors.orange);
      return;
    }

    setState(() {
      _downloadingFiles[url] = true;
    });

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Downloading $fileName...'),
            ],
          ),
        ),
      );

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download file');
      }

      Navigator.pop(context);

      final isImage = fileName.toLowerCase().endsWith('.jpg') ||
          fileName.toLowerCase().endsWith('.jpeg') ||
          fileName.toLowerCase().endsWith('.png') ||
          fileName.toLowerCase().endsWith('.gif');

      if (isImage) {
        final result = await ImageGallerySaverPlus.saveImage(
          Uint8List.fromList(response.bodyBytes),
          quality: 100,
          name: fileName,
        );

        if (result['isSuccess'] == true) {
          _showSnackBar('Image saved to gallery!', Colors.green);
        } else {
          _showSnackBar('Failed to save image', Colors.red);
        }
      } else {
        Directory? downloadDir;

        if (Platform.isAndroid) {
          if (await Permission.storage.isDenied) {
            final status = await Permission.storage.request();
            if (!status.isGranted) {
              _showSnackBar('Storage permission denied', Colors.red);
              setState(() => _downloadingFiles[url] = false);
              return;
            }
          }
          downloadDir = await getExternalStorageDirectory();
        } else if (Platform.isIOS) {
          downloadDir = await getApplicationDocumentsDirectory();
        }

        if (downloadDir != null) {
          final downloadsFolder =
              Directory('${downloadDir.path}/UniTrack_Downloads');
          if (!await downloadsFolder.exists()) {
            await downloadsFolder.create(recursive: true);
          }

          final file = File('${downloadsFolder.path}/$fileName');
          await file.writeAsBytes(response.bodyBytes);

          _showSnackBar(
              'Downloaded: $fileName to ${downloadsFolder.path}', Colors.green);

          final openFile = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Download Complete'),
              content: Text(
                  '$fileName has been downloaded. Do you want to open it?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Open'),
                ),
              ],
            ),
          );

          if (openFile == true) {
            if (Platform.isAndroid) {
              _showSnackBar(
                  'File saved. You can find it in UniTrack_Downloads folder.',
                  Colors.blue);
            }
          }
        }
      }
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showSnackBar('Error downloading file: $e', Colors.red);
    } finally {
      setState(() {
        _downloadingFiles[url] = false;
      });
    }
  }

  Future<void> _previewFile(
      String url, String fileName, String? fileType) async {
    try {
      final isImage = fileType != null &&
          (fileType.toLowerCase().contains('jpg') ||
              fileType.toLowerCase().contains('jpeg') ||
              fileType.toLowerCase().contains('png') ||
              fileType.toLowerCase().contains('gif'));

      if (isImage) {
        // Show image preview dialog
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.black,
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
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image,
                                color: Colors.white, size: 50),
                            SizedBox(height: 10),
                            Text('Failed to load image',
                                style: TextStyle(color: Colors.white)),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // For other files, offer download
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Preview Not Available'),
            content: Text(
                'This file type cannot be previewed. Do you want to download it?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Download'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await _downloadFile(url, fileName);
        }
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _getTargetColor(String? targetType) {
    switch (targetType) {
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

  IconData _getTargetIcon(String? targetType) {
    switch (targetType) {
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
        return '';
    }
  }

  String _formatDate(String? date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date);
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${d.day}/${d.month}/${d.year}';
    } catch (e) {
      return '';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Notices',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.green),
            onPressed: _fetchNotices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 60, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: TextStyle(color: Colors.red[600])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchNotices,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _notices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_outlined,
                              size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No notices available',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pull to refresh',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchNotices,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(15),
                        itemCount: _notices.length,
                        itemBuilder: (context, index) =>
                            _buildNoticeCard(_notices[index]),
                      ),
                    ),
    );
  }

  Widget _buildNoticeCard(Map<String, dynamic> notice) {
    final targetColor = _getTargetColor(notice['target_type']);
    final icon = _getTargetIcon(notice['target_type']);
    final targetLabel = _getTargetLabel(notice);
    final message = notice['message'] ?? '';
    final title = notice['title'] ?? 'Untitled';
    final hasAttachment = notice['attachment_url'] != null &&
        notice['attachment_url'].toString().isNotEmpty;
    final attachmentUrl = notice['attachment_url'] ?? '';
    final attachmentName = notice['attachment_name'] ?? 'Attachment';
    final attachmentType = notice['attachment_type'];
    final isDownloading = _downloadingFiles[attachmentUrl] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border(left: BorderSide(color: targetColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey[100]!,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: targetColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: targetColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: targetColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              targetLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: targetColor,
                              ),
                            ),
                          ),
                          if (hasAttachment)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attachment, size: 10),
                                  SizedBox(width: 2),
                                  Text('Attachment',
                                      style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDate(notice['created_at']),
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasAttachment)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isDownloading
                          ? null
                          : () => _previewFile(
                              attachmentUrl, attachmentName, attachmentType),
                      icon: Icon(Icons.visibility, color: Colors.blue[600]),
                      label: const Text('Preview'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue[600],
                        side: BorderSide(color: Colors.blue[600]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isDownloading
                          ? null
                          : () => _downloadFile(attachmentUrl, attachmentName),
                      icon: isDownloading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download),
                      label:
                          Text(isDownloading ? 'Downloading...' : 'Download'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                Icon(Icons.person, size: 12, color: Colors.green[400]),
                const SizedBox(width: 4),
                Text(
                  'By: ${notice['admin_name'] ?? 'Admin'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
