import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/ai/ai_inspector_page.dart';
import 'package:uni_track/analytics/analytics.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uni_track/services/mobile_data_service.dart';

class AdminIssuesPage extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminIssuesPage({super.key, required this.adminData});

  @override
  State<AdminIssuesPage> createState() => _AdminIssuesPageState();
}

class _AdminIssuesPageState extends State<AdminIssuesPage> {
  final _supabase = Supabase.instance.client;
  final _data = MobileDataService();
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _filteredIssues = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';
  Map<String, bool> _expandedStates = {};

  @override
  void initState() {
    super.initState();
    _fetchAssignedIssues();
  }

  Future<void> _fetchAssignedIssues() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filter = _selectedFilter == 'All'
          ? null
          : _selectedFilter == 'In Progress'
              ? 'UNDER_REVIEW'
              : _selectedFilter.toUpperCase();
      final response = await _data.getAdminComplaints(
        status: filter,
        limit: 200,
        adminData: widget.adminData,
      );

      final issues = List<Map<String, dynamic>>.from(
        response['complaints'] ?? [],
      ).map(_normalizeComplaintForLegacyUi).toList();

      await _enrichIssuesWithDetails(issues);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load issues: $e';
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _normalizeComplaintForLegacyUi(
      Map<String, dynamic> complaint) {
    final office = _mapOrNull(complaint['office']);
    final category = _mapOrNull(complaint['category']);
    final priority = _mapOrNull(complaint['priority']);
    final studentInfo = _mapOrNull(complaint['student_info']);
    final attachments = complaint['attachments'] as List? ?? [];
    final firstAttachment = attachments.isNotEmpty && attachments.first is Map
        ? attachments.first as Map<String, dynamic>
        : <String, dynamic>{};

    return {
      ...complaint,
      'assigned_office_id': office?['id'],
      'offices': office,
      'original_office': office,
      'issue_categories': category,
      'issue_priorities': priority,
      'student_email': studentInfo?['email'],
      'student_name': studentInfo?['full_name'],
      'student_phone': studentInfo?['phone'],
      'college_id': studentInfo?['college_id'],
      'course_id': studentInfo?['course_id'],
      'attachment_url': firstAttachment['fileUrl'],
      'attachment_name': firstAttachment['fileName'],
      'attachment_type': firstAttachment['fileType'],
      'attachment_size': firstAttachment['fileSize'],
      'escalation_level': complaint['current_escalation_level'] ?? 0,
      'escalation_history': complaint['statusHistory'] ?? [],
    };
  }

  Future<void> _enrichIssuesWithDetails(
      List<Map<String, dynamic>> response) async {
    final List<Map<String, dynamic>> enrichedIssues = [];

    for (var issue in response) {
      Map<String, dynamic> enriched = Map<String, dynamic>.from(issue);

      // Debug - check if attachment exists
      final hasAttachment = issue['attachment_url'] != null &&
          issue['attachment_url'].toString().isNotEmpty;

      if (hasAttachment) {
      } else {}

      // Fetch office info
      if (issue['assigned_office_id'] != null) {
        try {
          final officeData = await _supabase
              .from('offices')
              .select('name, building, room_number, level')
              .eq('id', issue['assigned_office_id'])
              .maybeSingle();
          enriched['offices'] = officeData;
        } catch (e) {}
      }

      // Fetch original office
      if (issue['original_office_id'] != null) {
        try {
          final originalOfficeData = await _supabase
              .from('offices')
              .select('name, level')
              .eq('id', issue['original_office_id'])
              .maybeSingle();
          enriched['original_office'] = originalOfficeData;
        } catch (e) {}
      }

      // Fetch student info
      if (issue['student_id'] != null) {
        try {
          final studentData = await _supabase
              .from('students')
              .select('full_name, email, student_id, phone')
              .eq('id', issue['student_id'])
              .maybeSingle();
          enriched['student_info'] = studentData;
        } catch (e) {}
      }
      enrichedIssues.add(enriched);
    }

    if (mounted) {
      setState(() {
        _issues = enrichedIssues;
        _filterIssues(_selectedFilter);
        _isLoading = false;
      });
    }
  }

  void _filterIssues(String filter) {
    setState(() {
      _selectedFilter = filter;
      if (filter == 'All') {
        _filteredIssues = List.from(_issues);
      } else if (filter == 'Escalated') {
        _filteredIssues = _issues.where((i) => i['escalated'] == true).toList();
      } else {
        _filteredIssues = _issues
            .where(
              (i) =>
                  i['status']?.toString().toUpperCase() == filter.toUpperCase(),
            )
            .toList();
      }
    });
  }

  Future<void> _updateIssueStatus(
    String issueId,
    String newStatus, {
    String? rejectionReason,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (newStatus == 'rejected') {
        updates['rejection_reason'] = rejectionReason ?? 'No reason provided';
        updates['rejected_at'] = DateTime.now().toIso8601String();
        updates['rejected_by_name'] = widget.adminData['full_name'];
        updates['should_escalate'] = false;
      }

      await _data.updateComplaintStatus(
        complaintId: issueId,
        status: newStatus,
        rejectionReason: rejectionReason,
      );

      _showSnackBar('Status updated to: $newStatus', Colors.green);
      _fetchAssignedIssues();
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _escalateIssue(Map<String, dynamic> issue) async {
    final currentOffice = issue['offices'];
    final currentLevel = currentOffice?['level'] ?? 0;
    final nextLevel = currentLevel + 1;

    final higherOffice = await _supabase
        .from('offices')
        .select('id, name, level')
        .eq('level', nextLevel)
        .maybeSingle();

    if (higherOffice == null) {
      _showSnackBar('No higher office available for escalation', Colors.orange);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Escalate Issue',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Office: ${currentOffice?['name'] ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Escalate to: ${higherOffice['name']}'),
            const SizedBox(height: 16),
            const Text(
                'The issue will be forwarded to the higher office for further action.'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child:
                const Text('Escalate', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _data.patchComplaintAction(
          complaintId: issue['id'].toString(),
          action: 'force-escalate',
        );

        _showSnackBar(
            'Issue escalated to ${higherOffice['name']}', Colors.purple);
        _fetchAssignedIssues();
      } catch (e) {
        _showSnackBar('Error escalating issue: $e', Colors.red);
      }
    }
  }

  Future<void> _resolveIssue(String issueId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Issue',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'Mark this issue as resolved? The student will be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Resolve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateIssueStatus(issueId, 'resolved');
    }
  }

  Future<void> _addComment(String issueId) async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Comment/Feedback',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This comment will be visible to the student.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter your feedback or comment...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty)
                Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        await _data.addComment(
          complaintId: issueId,
          comment: controller.text.trim(),
        );
        _showSnackBar('Comment added successfully', Colors.green);
      } catch (e) {
        _showSnackBar('Error adding comment: $e', Colors.red);
      }
    }
    controller.dispose();
  }

  Future<void> _viewComments(String issueId, String issueTitle) async {
    try {
      final comments = await _data.getComments(issueId);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Comments for: $issueTitle',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Expanded(
                  child: comments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 60, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('No comments yet',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: comments.length,
                          itemBuilder: (context, index) =>
                              _buildCommentBubble(comments[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('Error loading comments: $e', Colors.red);
    }
  }

  Future<void> _previewAttachment(String url, String fileName) async {
    if (url.isEmpty) {
      _showSnackBar('No attachment available', Colors.orange);
      return;
    }

    try {
      final isImage = fileName.toLowerCase().contains('.jpg') ||
          fileName.toLowerCase().contains('.jpeg') ||
          fileName.toLowerCase().contains('.png') ||
          fileName.toLowerCase().contains('.gif');

      if (isImage) {
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
                            child:
                                CircularProgressIndicator(color: Colors.white));
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              color: Colors.white, size: 50),
                          SizedBox(height: 10),
                          Text('Failed to load image',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
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
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('Cannot preview this file', Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar('Error previewing file: $e', Colors.red);
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    if (url.isEmpty) {
      _showSnackBar('No attachment available', Colors.orange);
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('Cannot download this file', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error downloading attachment: $e', Colors.red);
    }
  }

  Widget _buildCommentBubble(Map<String, dynamic> comment) {
    final isAdmin = comment['admin_id'] != null ||
        comment['user_role']?.toString().toUpperCase() == 'ADMIN';
    final name = comment['admin_name'] ??
        comment['student_name'] ??
        comment['user_name'] ??
        (isAdmin ? 'Admin' : 'Student');
    final text = comment['comment'] ?? comment['new_status'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isAdmin ? Colors.green[50] : Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isAdmin ? Colors.green[700] : Colors.blue[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(_formatDate(comment['created_at']?.toString()),
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
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

  String _formatDate(String? date) {
    if (date == null) return 'N/A';
    try {
      final d = DateTime.parse(date);
      return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return date;
    }
  }

  String _getDaysAgo(String? date) {
    if (date == null) return '';
    try {
      final days = DateTime.now().difference(DateTime.parse(date)).inDays;
      if (days == 0) return 'Today';
      if (days == 1) return 'Yesterday';
      return '$days days ago';
    } catch (e) {
      return '';
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes == 0) return '';
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

  bool _canPerformActions(Map<String, dynamic> issue) {
    final status = issue['status']?.toString() ?? '';
    final isEscalated = issue['escalated'] == true;
    return !isEscalated &&
        status.toUpperCase() != 'RESOLVED' &&
        status.toUpperCase() != 'REJECTED';
  }

  Color _getPriorityColor(String? name) {
    switch (name?.toLowerCase()) {
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

  String _getPriorityIcon(String? name) {
    switch (name?.toLowerCase()) {
      case 'low':
        return '🔵';
      case 'medium':
        return '🟠';
      case 'high':
        return '🔴';
      case 'critical':
        return '⚠️';
      default:
        return '📌';
    }
  }

  Color _getStatusColor(String? status, bool isEscalated) {
    if (isEscalated) return Colors.purple;
    switch (status?.toLowerCase()) {
      case 'resolved':
      case 'resolve':
        return Colors.green;
      case 'in_progress':
      case 'under_review':
        return Colors.blue;
      case 'pending':
      case 'open':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
      case 'resolve':
        return Icons.check_circle;
      case 'in_progress':
      case 'under_review':
        return Icons.play_circle;
      case 'pending':
      case 'open':
        return Icons.hourglass_empty;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.warning;
    }
  }

  Future<void> _showRejectDialog(String issueId) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Issue',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejection.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Reason for rejection...',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty)
                Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      await _updateIssueStatus(issueId, 'rejected',
          rejectionReason: controller.text.trim());
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _issues.where((i) => i['status'] == 'pending').length;
    final inProgressCount =
        _issues.where((i) => i['status'] == 'in_progress').length;
    final escalatedCount = _issues.where((i) => i['escalated'] == true).length;
    final resolvedCount =
        _issues.where((i) => i['status'] == 'resolved').length;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Assigned Issues',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                fontSize: 20)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.green),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      AnalyticsPage(userData: widget.adminData, isAdmin: true)),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.green),
              onPressed: _fetchAssignedIssues),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                _buildStatCard('Pending', pendingCount.toString(),
                    Colors.orange, Icons.hourglass_empty),
                const SizedBox(width: 8),
                _buildStatCard('In Progress', inProgressCount.toString(),
                    Colors.blue, Icons.play_circle),
                const SizedBox(width: 8),
                _buildStatCard('Escalated', escalatedCount.toString(),
                    Colors.purple, Icons.arrow_upward),
                const SizedBox(width: 8),
                _buildStatCard('Resolved', resolvedCount.toString(),
                    Colors.green, Icons.check_circle),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Pending'),
                  const SizedBox(width: 8),
                  _buildFilterChip('In Progress'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Escalated'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Resolved'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Rejected'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.green)))
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
                            ElevatedButton(
                              onPressed: _fetchAssignedIssues,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredIssues.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 80, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text('No issues assigned',
                                    style: TextStyle(
                                        fontSize: 18, color: Colors.grey[600])),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchAssignedIssues,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(15),
                              itemCount: _filteredIssues.length,
                              itemBuilder: (context, index) =>
                                  _buildIssueCard(_filteredIssues[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(count,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final selected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => _filterIssues(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.green : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? Colors.green : Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isEmpty) return null;
    return null;
  }

  List<dynamic>? _listOrNull(dynamic value) {
    if (value is List) return value;
    return null;
  }

  Widget _buildIssueCard(Map<String, dynamic> issue) {
    final category = _mapOrNull(issue['issue_categories']);
    final priority = _mapOrNull(issue['issue_priorities']);
    final priorityName = priority?['name']?.toString() ?? 'N/A';
    final priorityColor = _getPriorityColor(priorityName);
    final status = issue['status']?.toString() ?? 'pending';
    final isEscalated = issue['escalated'] == true;
    final escalationLevel = issue['escalation_level'] ?? 0;
    final statusColor = _getStatusColor(status, isEscalated);
    final studentInfo = _mapOrNull(issue['student_info']);
    final studentName = studentInfo?['full_name']?.toString() ??
        issue['student_name']?.toString() ??
        'Unknown';

    // Check for attachment - handle null values properly
    final hasAttachment = issue['attachment_url'] != null &&
        issue['attachment_url'].toString().isNotEmpty;

    final attachmentUrl = issue['attachment_url'] ?? '';
    final attachmentName = issue['attachment_name'] ?? 'Attachment';
    final attachmentType = issue['attachment_type'];
    final attachmentSize = issue['attachment_size'];

    final escalationHistory = _listOrNull(issue['escalation_history']) ?? [];
    final originalOffice = _mapOrNull(issue['original_office']);
    final currentOffice = _mapOrNull(issue['offices']);
    final isFromDifferentOffice = originalOffice != null &&
        currentOffice != null &&
        originalOffice['id'] != currentOffice['id'];
    final canAct = _canPerformActions(issue);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isEscalated
                ? Colors.purple.withOpacity(0.5)
                : Colors.grey[200]!,
            width: isEscalated ? 2 : 1),
        boxShadow: [
          BoxShadow(
              color: Colors.grey[100]!,
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleExpand(issue),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            issue['title']?.toString() ?? 'Untitled',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: priorityColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: priorityColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_getPriorityIcon(priorityName),
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              Text(priorityName.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: priorityColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getStatusIcon(status),
                                  size: 14, color: statusColor),
                              const SizedBox(width: 4),
                              Text(status.toUpperCase().replaceAll('_', ' '),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor)),
                            ],
                          ),
                        ),
                        if (isEscalated) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.purple.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.trending_up,
                                    size: 12, color: Colors.purple),
                                const SizedBox(width: 4),
                                Text('ESCALATED L$escalationLevel',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Attachment Badge - Only show if attachment exists
                    if (hasAttachment)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getFileIcon(attachmentType),
                                size: 14, color: Colors.blue[700]),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                attachmentName,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.blue[700]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Row(
                      children: [
                        CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.grey[200],
                            child: const Icon(Icons.person,
                                size: 16, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(studentName,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              Text(_getDaysAgo(issue['created_at']?.toString()),
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: Colors.grey[400], size: 20),
                      ],
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(height: 0),
                secondChild: _buildExpandedContent(
                    issue,
                    studentName,
                    studentInfo,
                    category,
                    priorityName,
                    canAct,
                    isFromDifferentOffice,
                    originalOffice,
                    currentOffice,
                    escalationHistory,
                    hasAttachment,
                    attachmentUrl,
                    attachmentName,
                    attachmentType,
                    attachmentSize),
                crossFadeState: _isExpanded(issue)
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(
    Map<String, dynamic> issue,
    String studentName,
    Map<String, dynamic>? studentInfo,
    Map<String, dynamic>? category,
    String priorityName,
    bool canAct,
    bool isFromDifferentOffice,
    Map<String, dynamic>? originalOffice,
    Map<String, dynamic>? currentOffice,
    List escalationHistory,
    bool hasAttachment,
    String attachmentUrl,
    String attachmentName,
    String? attachmentType,
    int? attachmentSize,
  ) {
    final status = issue['status']?.toString() ?? 'pending';
    final escalationLevel = issue['escalation_level'] ?? 0;
    final maxEscalation = issue['max_escalation_level'] ?? 5;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFromDifferentOffice)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.purple[50]!, Colors.purple[100]!]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: Colors.purple[100],
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.swap_horiz,
                            color: Colors.purple[700], size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Issue Escalated From Another Office',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple[800])),
                            Text(
                                'Originally from: ${originalOffice?['name'] ?? 'Unknown'} (Level ${originalOffice?['level'] ?? '?'})',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.purple[600])),
                            Text(
                                'Currently at: ${currentOffice?['name'] ?? 'Unknown'} (Level ${currentOffice?['level'] ?? '?'})',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.purple[600])),
                            Text(
                                'Escalation Level: $escalationLevel of $maxEscalation',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple[700])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (escalationHistory.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ESCALATION HISTORY',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                  const SizedBox(height: 8),
                  ...escalationHistory.map((history) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_forward,
                                size: 12, color: Colors.purple),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Escalated to Level ${history['escalation_level']}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                  Text(
                                      'From: ${history['from_office']?['name'] ?? 'Unknown'} → To: ${history['to_office']?['name'] ?? 'Unknown'}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600])),
                                  Text(_formatDate(history['escalated_at']),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500])),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ISSUE DETAILS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
                const SizedBox(height: 12),
                _buildDetailRow('Category',
                    category?['name']?.toString() ?? 'N/A', Icons.category),
                const SizedBox(height: 8),
                _buildDetailRow('Location',
                    issue['location']?.toString() ?? 'N/A', Icons.location_on),
                const SizedBox(height: 8),
                _buildDetailRow('Priority', priorityName, Icons.priority_high),
                const SizedBox(height: 8),
                _buildDetailRow(
                    'Resolution Time',
                    '${issue['issue_priorities']?['days_to_resolve'] ?? 0} days',
                    Icons.timer),
                const SizedBox(height: 8),
                _buildDetailRow(
                    'Reported On',
                    _formatDate(issue['created_at']?.toString()),
                    Icons.calendar_today),
                const Divider(height: 24),
                const Text('STUDENT INFORMATION',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
                const SizedBox(height: 12),
                _buildDetailRow('Name', studentName, Icons.person),
                const SizedBox(height: 8),
                _buildDetailRow(
                    'Email',
                    studentInfo?['email']?.toString() ??
                        issue['student_email']?.toString() ??
                        'N/A',
                    Icons.email),
                if (studentInfo?['phone'] != null)
                  _buildDetailRow('Phone',
                      studentInfo?['phone']?.toString() ?? 'N/A', Icons.phone),
                if (issue['student_id'] != null)
                  _buildDetailRow('Student ID', issue['student_id'].toString(),
                      Icons.badge),
                const Divider(height: 24),
                const Text('DESCRIPTION',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      issue['description']?.toString() ??
                          'No description provided',
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),

                // Attachment Section - Only show if attachment exists
                if (hasAttachment && attachmentUrl.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text('ATTACHMENT',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(_getFileIcon(attachmentType),
                                color: Colors.green[600], size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(attachmentName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14)),
                                  if (attachmentSize != null &&
                                      attachmentSize > 0)
                                    Text(_formatFileSize(attachmentSize),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600])),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _previewAttachment(
                                    attachmentUrl, attachmentName),
                                icon: const Icon(Icons.visibility),
                                label: const Text('Preview'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _downloadFile(
                                    attachmentUrl, attachmentName),
                                icon: const Icon(Icons.download),
                                label: const Text('Download'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (status.toUpperCase() == 'REJECTED')
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.cancel, color: Colors.red[700], size: 18),
                    const SizedBox(width: 8),
                    Text('Rejection Reason',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700])),
                  ]),
                  const SizedBox(height: 6),
                  Text(issue['rejection_reason'] ?? 'No reason provided',
                      style: TextStyle(fontSize: 12, color: Colors.red[600])),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AiInspectorPage(
                        issue: issue,
                        userData: widget.adminData,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('AI Inspect'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addComment(issue['id'].toString()),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Add Comment'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _viewComments(
                      issue['id'].toString(), issue['title'] ?? 'Issue'),
                  icon: const Icon(Icons.comment, size: 18),
                  label: const Text('View Comments'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green)),
                ),
              ),
            ],
          ),
          if (canAct) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (status.toUpperCase() == 'PENDING' ||
                    status.toUpperCase() == 'OPEN')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateIssueStatus(
                          issue['id'].toString(), 'UNDER_REVIEW'),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start Working'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue),
                    ),
                  ),
                if (status.toUpperCase() == 'UNDER_REVIEW' ||
                    status.toUpperCase() == 'IN_PROGRESS') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _resolveIssue(issue['id'].toString()),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Resolve Issue'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _escalateIssue(issue),
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      label: const Text('Escalate'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(issue['id'].toString()),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _toggleExpand(Map<String, dynamic> issue) {
    final id = issue['id'].toString();
    setState(() {
      _expandedStates[id] = !(_expandedStates[id] ?? false);
    });
  }

  bool _isExpanded(Map<String, dynamic> issue) {
    final id = issue['id'].toString();
    return _expandedStates[id] ?? false;
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 10),
        SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500))),
        Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, color: Colors.black87))),
      ],
    );
  }
}
