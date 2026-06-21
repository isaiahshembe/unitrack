import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:html' as html;

class IssueTrackingPage extends StatefulWidget {
  final Map<String, dynamic> issue;
  final Map<String, dynamic>? userData;

  const IssueTrackingPage({super.key, required this.issue, this.userData});

  @override
  State<IssueTrackingPage> createState() => _IssueTrackingPageState();
}

class _IssueTrackingPageState extends State<IssueTrackingPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingComments = false;
  final _commentController = TextEditingController();
  bool _isSubmittingComment = false;

  // Store complete issue data with relationships
  Map<String, dynamic>? _completeIssueData;
  bool _isLoadingIssue = true;

  @override
  void initState() {
    super.initState();
    _fetchCompleteIssueData();
    _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // FIX: Fetch complete issue data with all relationships
  Future<void> _fetchCompleteIssueData() async {
    setState(() => _isLoadingIssue = true);

    try {
      final response = await _supabase
          .from('issues')
          .select('''
            *,
            issue_categories (
              id,
              name,
              description,
              priority_id
            ),
            issue_priorities (
              id,
              name,
              days_to_resolve
            ),
            assigned_office:offices!issues_assigned_office_id_fkey (
              id,
              name,
              level,
              building,
              room_number
            ),
            original_office:offices!issues_original_office_id_fkey (
              id,
              name,
              level
            ),
            admins (
              id,
              full_name,
              email
            )
          ''')
          .eq('id', widget.issue['id'])
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          if (response != null) {
            _completeIssueData = Map<String, dynamic>.from(response);

            // Rename assigned_office to offices for compatibility
            if (_completeIssueData!['assigned_office'] != null) {
              _completeIssueData!['offices'] =
                  _completeIssueData!['assigned_office'];
            }
          } else {
            _completeIssueData = widget.issue;
          }
          _isLoadingIssue = false;
        });
      }
    } catch (e) {
      print('Error fetching issue details: $e');
      if (mounted) {
        setState(() {
          _completeIssueData = widget.issue;
          _isLoadingIssue = false;
        });
      }
    }
  }

  Future<void> _fetchComments() async {
    setState(() => _isLoadingComments = true);
    try {
      // FIX: Fetch all comments regardless of student_id or admin_id
      final response = await _supabase
          .from('issue_comments')
          .select('*')
          .eq('issue_id', widget.issue['id'])
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(response);
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingComments = false);
    }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;

    setState(() => _isSubmittingComment = true);

    try {
      await _supabase.from('issue_comments').insert({
        'issue_id': widget.issue['id'],
        'student_id': widget.userData?['id'],
        'student_name': widget.userData?['full_name'] ?? 'Student',
        'comment': _commentController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });

      _commentController.clear();
      await _fetchComments();

      if (mounted) {
        setState(() => _isSubmittingComment = false);
        _showSnackBar('Comment added successfully', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
        _showSnackBar('Error adding comment: $e', Colors.red);
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

  Future<void> _previewAttachment(String url, String fileName) async {
    try {
      final uri = Uri.parse(url);
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
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('Cannot preview this file', Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar('Error opening attachment: $e', Colors.red);
    }
  }

  void _downloadFile(String url, String fileName) {
    try {
      final anchor = html.AnchorElement(href: url);
      anchor.download = fileName;
      anchor.style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      _showSnackBar('Download started: $fileName', Colors.green);
    } catch (e) {
      html.window.open(url, '_blank');
      _showSnackBar('Opening file in new tab', Colors.blue);
    }
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
    // Use complete issue data if available
    final issueData = _completeIssueData ?? widget.issue;

    // FIX: Extract relationship data properly
    final category = issueData['issue_categories'] is Map
        ? issueData['issue_categories'] as Map<String, dynamic>
        : null;

    final priority = issueData['issue_priorities'] is Map
        ? issueData['issue_priorities'] as Map<String, dynamic>
        : null;

    final office = issueData['offices'] is Map
        ? issueData['offices'] as Map<String, dynamic>
        : null;

    final admin = issueData['admins'] is Map
        ? issueData['admins'] as Map<String, dynamic>
        : null;

    final status = issueData['status']?.toString() ?? 'pending';
    final escalationLevel = issueData['escalation_level'] ?? 0;
    final maxEscalationLevel = issueData['max_escalation_level'] ?? 3;
    final isEscalated = issueData['escalated'] == true;
    final isRejected = status == 'rejected';
    final rejectionReason = issueData['rejection_reason']?.toString();
    // FIX: Get days_to_resolve from priority relationship
    final daysToResolve = priority?['days_to_resolve'] ?? 0;
    final hasAttachment = issueData['attachment_url'] != null &&
        issueData['attachment_url'].toString().isNotEmpty;
    final attachmentUrl = issueData['attachment_url'] ?? '';
    final attachmentName = issueData['attachment_name'] ?? 'Attachment';
    final attachmentType = issueData['attachment_type'];

    // Show loading indicator while fetching complete data
    if (_isLoadingIssue) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Issue Tracking',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Issue Tracking',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              issueData['title']?.toString() ?? 'Untitled',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            if (isEscalated && escalationLevel > 0) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple.shade100, Colors.purple.shade50],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward,
                        color: Colors.purple.shade700, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Issue Escalated - Level $escalationLevel of $maxEscalationLevel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'This issue has been forwarded to a higher office for faster resolution.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.purple.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (isRejected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cancel, color: Colors.red[700], size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Issue Rejected',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                            ),
                          ),
                          if (rejectionReason != null &&
                              rejectionReason.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Reason: $rejectionReason',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildTrackingTimeline(status, escalationLevel, isEscalated,
                isRejected, maxEscalationLevel),
            const SizedBox(height: 24),
            _buildSectionCard(
              'Issue Details',
              Icons.info_outline,
              Colors.blue,
              [
                _buildDetailRow(
                    'Category', category?['name']?.toString() ?? 'N/A'),
                _buildDetailRow(
                    'Priority', priority?['name']?.toString() ?? 'N/A'),
                _buildDetailRow('Resolution Time', '$daysToResolve day(s)'),
                _buildDetailRow(
                    'Location', issueData['location']?.toString() ?? 'N/A'),
                _buildDetailRow('Reported',
                    _formatDate(issueData['created_at']?.toString())),
                _buildDetailRow('Status',
                    _getStatusLabel(status, isEscalated, escalationLevel)),
                if (isEscalated && escalationLevel > 0) ...[
                  _buildDetailRow('Escalation Level',
                      'Level $escalationLevel of $maxEscalationLevel'),
                  _buildDetailRow('Escalated On',
                      _formatDate(issueData['escalated_at']?.toString())),
                ],
                if (isRejected) ...[
                  _buildDetailRow('Rejected On',
                      _formatDate(issueData['rejected_at']?.toString())),
                  if (issueData['rejected_by_name'] != null)
                    _buildDetailRow('Rejected By',
                        issueData['rejected_by_name'].toString()),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (hasAttachment) ...[
              _buildSectionCard(
                'Attachment',
                Icons.attachment,
                Colors.orange,
                [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getFileIcon(attachmentType),
                              color: Colors.green[600],
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    attachmentName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatFileSize(
                                        issueData['attachment_size']),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
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
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
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
                                  backgroundColor: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (office != null || admin != null) ...[
              _buildSectionCard(
                'Assignment Details',
                Icons.business,
                isEscalated && escalationLevel > 0
                    ? Colors.purple
                    : Colors.green,
                [
                  if (office != null) ...[
                    _buildDetailRow(
                        'Current Office', office['name']?.toString() ?? 'N/A'),
                    _buildDetailRow(
                        'Office Level', office['level']?.toString() ?? 'N/A'),
                    _buildDetailRow(
                        'Building', office['building']?.toString() ?? 'N/A'),
                    _buildDetailRow(
                        'Room', office['room_number']?.toString() ?? 'N/A'),
                  ],
                  if (admin != null)
                    _buildDetailRow('Assigned Admin',
                        admin['full_name']?.toString() ?? 'N/A'),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _buildSectionCard('Description', Icons.description, Colors.orange, [
              Text(
                issueData['description']?.toString() ??
                    'No description provided',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ]),
            const SizedBox(height: 16),
            if (isRejected && rejectionReason != null) ...[
              _buildSectionCard(
                'Admin Response',
                Icons.feedback,
                Colors.red,
                [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[100]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Rejection Reason',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          rejectionReason,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _buildSectionCard('Status Updates', Icons.timeline, Colors.teal, [
              _buildUpdateItem(
                'Issue Submitted',
                'Your issue has been submitted and assigned for review.',
                issueData['created_at']?.toString(),
                Colors.blue,
              ),
              if (issueData['status'] == 'in_progress')
                _buildUpdateItem(
                  'Under Review',
                  'An administrator is currently reviewing your issue.',
                  issueData['updated_at']?.toString(),
                  Colors.orange,
                ),
              if (isEscalated && escalationLevel > 0)
                _buildUpdateItem(
                  'Issue Escalated to Level $escalationLevel',
                  'Your issue has been forwarded to a higher office for faster resolution.',
                  issueData['escalated_at']?.toString(),
                  Colors.purple,
                ),
              if (isRejected)
                _buildUpdateItem(
                  'Issue Rejected',
                  rejectionReason ??
                      'Your issue has been rejected by the administrator.',
                  issueData['rejected_at']?.toString(),
                  Colors.red,
                ),
              if (status == 'resolved')
                _buildUpdateItem(
                  'Issue Resolved',
                  'Your issue has been resolved successfully.',
                  issueData['updated_at']?.toString(),
                  Colors.green,
                ),
            ]),
            const SizedBox(height: 16),
            _buildSectionCard('Feedback & Comments', Icons.chat, Colors.teal, [
              if (_isLoadingComments)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_comments.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 40, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No feedback yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Comments from the admin will appear here',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                ..._comments.map((comment) => _buildCommentItem(comment)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(children: [
                  TextField(
                    controller: _commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment or question...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${_commentController.text.length}/500',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed:
                              _isSubmittingComment ? null : _submitComment,
                          icon: _isSubmittingComment
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send, size: 16),
                          label: const Text('Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildTrackingTimeline(
    String status,
    int escalationLevel,
    bool isEscalated,
    bool isRejected,
    int maxEscalationLevel,
  ) {
    final submittedColor = Colors.blue;
    final reviewedColor = _getReviewedColor(status, isEscalated, isRejected);
    final escalatedColor =
        isEscalated && escalationLevel > 0 ? Colors.purple : Colors.grey;
    final resolvedColor = _getResolvedColor(status, isRejected);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isRejected ? Colors.red[200]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTimelineStep('Submitted', true, Icons.send, submittedColor),
              Expanded(
                child: Container(
                  height: 2,
                  color: _isStepComplete(
                          'submitted', status, isEscalated, isRejected)
                      ? submittedColor
                      : Colors.grey[300],
                ),
              ),
              _buildTimelineStep(
                'In Review',
                _isStepComplete('reviewed', status, isEscalated, isRejected),
                Icons.search,
                reviewedColor,
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: isEscalated && escalationLevel > 0
                      ? Colors.purple
                      : _isStepComplete(
                              'escalated', status, isEscalated, isRejected)
                          ? Colors.grey[300]
                          : Colors.grey[300],
                ),
              ),
              _buildTimelineStep(
                'Escalated',
                isEscalated && escalationLevel > 0,
                Icons.arrow_upward,
                escalatedColor,
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: status == 'resolved'
                      ? Colors.green
                      : isRejected
                          ? Colors.red
                          : Colors.grey[300],
                ),
              ),
              _buildTimelineStep(
                isRejected ? 'Rejected' : 'Resolved',
                status == 'resolved' || isRejected,
                isRejected ? Icons.cancel : Icons.check_circle,
                resolvedColor,
              ),
            ],
          ),
          if (isEscalated && escalationLevel > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple[100]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.purple[600]),
                  const SizedBox(width: 6),
                  Text(
                    'Escalation Level $escalationLevel of $maxEscalationLevel',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.purple[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isRejected) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[100]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 14, color: Colors.red[600]),
                  const SizedBox(width: 6),
                  Text(
                    'Process stopped at rejection',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineStep(
      String label, bool isComplete, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isComplete ? color.withOpacity(0.1) : Colors.grey[100],
            shape: BoxShape.circle,
            border: Border.all(
              color: isComplete ? color : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isComplete ? color : Colors.grey[400],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: isComplete ? color : Colors.grey[500],
            fontWeight: isComplete ? FontWeight.w600 : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  bool _isStepComplete(
      String step, String status, bool isEscalated, bool isRejected) {
    switch (step) {
      case 'submitted':
        return true;
      case 'reviewed':
        return status == 'in_progress' ||
            isEscalated ||
            status == 'resolved' ||
            isRejected;
      case 'escalated':
        return isEscalated;
      default:
        return false;
    }
  }

  Color _getReviewedColor(String status, bool isEscalated, bool isRejected) {
    if (isRejected) return Colors.red;
    if (isEscalated) return Colors.purple;
    if (status == 'in_progress' || status == 'resolved') return Colors.blue;
    return Colors.grey;
  }

  Color _getResolvedColor(String status, bool isRejected) {
    if (isRejected) return Colors.red;
    if (status == 'resolved') return Colors.green;
    return Colors.grey;
  }

  Widget _buildSectionCard(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey[50]!,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateItem(
      String title, String message, String? dateTime, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(dateTime),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // FIXED: Comment item that shows both student and admin comments
  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final isAdmin = comment['admin_id'] != null && comment['admin_id'] != '';
    final name = isAdmin
        ? (comment['admin_name'] ?? 'Admin')
        : (comment['student_name'] ?? 'Student');
    final role = isAdmin ? 'Admin' : 'You';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isAdmin ? Colors.blue[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAdmin ? Colors.blue[200]! : Colors.green[200]!,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          isAdmin ? Colors.blue[100] : Colors.green[100],
                      child: Icon(
                        isAdmin ? Icons.admin_panel_settings : Icons.person,
                        size: 14,
                        color: isAdmin ? Colors.blue[700] : Colors.green[700],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                isAdmin ? Colors.blue[700] : Colors.green[700],
                          ),
                        ),
                        Text(
                          role,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      _formatTimeAgo(comment['created_at']?.toString()),
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  comment['comment'] ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTime;
    }
  }

  String _formatTimeAgo(String? dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime);
      final difference = DateTime.now().difference(date);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
      if (difference.inHours < 24) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return _formatDate(dateTime);
    } catch (e) {
      return '';
    }
  }

  String _getStatusLabel(String status, bool isEscalated, int escalationLevel) {
    if (isEscalated && escalationLevel > 1)
      return 'Escalated Level $escalationLevel';
    if (isEscalated) return 'Escalated';

    switch (status.toLowerCase()) {
      case 'resolved':
        return 'Resolved ✅';
      case 'in_progress':
        return 'In Progress';
      case 'pending':
        return 'Pending Review';
      case 'escalated':
        return 'Escalated';
      case 'rejected':
        return 'Rejected ❌';
      default:
        return status;
    }
  }
}
