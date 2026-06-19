import 'package:flutter/material.dart';
import 'package:uni_track/ai/ai_inspector_page.dart';
import 'package:uni_track/analytics/analytics.dart';
import 'package:uni_track/services/mobile_data_service.dart';
import 'package:uni_track/students/report_issues.dart';
import 'package:uni_track/students/issue_tracking.dart';

class IssuesPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const IssuesPage({super.key, this.userData});

  @override
  State<IssuesPage> createState() => _IssuesPageState();
}

class _IssuesPageState extends State<IssuesPage> {
  final _data = MobileDataService();
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _filteredIssues = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _fetchIssues();
  }

  Future<void> _fetchIssues() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _data.getComplaints(
          limit: 50, studentId: widget.userData?['id']?.toString());
      final complaints =
          List<Map<String, dynamic>>.from(response['complaints'] ?? []);

      if (mounted) {
        setState(() {
          _issues = complaints;
          _filterIssues(_selectedFilter);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load issues. Pull to refresh. $e';
          _isLoading = false;
        });
      }
    }
  }

  void _filterIssues(String filter) {
    setState(() {
      _selectedFilter = filter;
      if (filter == 'All') {
        _filteredIssues = List.from(_issues);
      } else if (filter == 'Escalated') {
        _filteredIssues = _issues
            .where((issue) =>
                issue['escalated'] == true || issue['status'] == 'ESCALATED')
            .toList();
      } else {
        _filteredIssues = _issues
            .where(
              (issue) =>
                  issue['status']?.toString().toLowerCase() ==
                  filter.toLowerCase().replaceAll(' ', '_'),
            )
            .toList();
      }
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

  String _getPriorityIcon(String? priorityName) {
    switch (priorityName?.toLowerCase()) {
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
      case 'open':
        return Colors.green;
      case 'in_progress':
      case 'under_review':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'escalated':
      case 'critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status, bool isEscalated, int escalationLevel,
      int maxEscalationLevel) {
    if (isEscalated) {
      return 'ESCALATED L$escalationLevel/$maxEscalationLevel';
    }

    switch (status?.toLowerCase()) {
      case 'resolved':
        return 'RESOLVED';
      case 'open':
        return 'OPEN';
      case 'in_progress':
      case 'under_review':
        return 'IN PROGRESS';
      case 'pending':
        return 'PENDING';
      case 'rejected':
        return 'REJECTED';
      case 'escalated':
        return 'ESCALATED';
      case 'critical':
        return 'CRITICAL';
      default:
        return status?.toUpperCase() ?? 'PENDING';
    }
  }

  IconData _getStatusIcon(String? status, bool isEscalated) {
    if (isEscalated) return Icons.trending_up;

    switch (status?.toLowerCase()) {
      case 'resolved':
        return Icons.check_circle;
      case 'open':
        return Icons.inbox;
      case 'in_progress':
      case 'under_review':
        return Icons.play_circle;
      case 'pending':
        return Icons.hourglass_empty;
      case 'rejected':
        return Icons.cancel;
      case 'escalated':
      case 'critical':
        return Icons.trending_up;
      default:
        return Icons.hourglass_empty;
    }
  }

  String _getDaysAgo(String? dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime);
      final days = DateTime.now().difference(date).inDays;
      if (days == 0) return 'Today';
      if (days == 1) return 'Yesterday';
      return '$days days ago';
    } catch (e) {
      return '';
    }
  }

  String _priorityNameFromIssue(dynamic priority) {
    if (priority is Map) return priority['name']?.toString() ?? 'N/A';
    if (priority is String) return priority;
    if (priority is int) {
      switch (priority) {
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
    return 'N/A';
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
    final totalCount = _issues.length;
    final pendingCount = _issues
        .where((i) => i['status'] == 'OPEN' || i['status'] == 'UNDER_REVIEW')
        .length;
    final escalatedCount = _issues
        .where((i) => i['escalated'] == true || i['status'] == 'ESCALATED')
        .length;
    final resolvedCount =
        _issues.where((i) => i['status'] == 'RESOLVED').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'My Issues',
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
            icon: const Icon(Icons.analytics_outlined, color: Colors.green),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AnalyticsPage(
                  userData: widget.userData!,
                  isAdmin: false,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.green),
            onPressed: _fetchIssues,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 2,
                  child: _buildStatCard(
                    'Total',
                    totalCount.toString(),
                    Colors.blue,
                    Icons.bug_report,
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 2,
                  child: _buildStatCard(
                    'Pending',
                    pendingCount.toString(),
                    Colors.orange,
                    Icons.hourglass_empty,
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 2,
                  child: _buildStatCard(
                    'Escalated',
                    escalatedCount.toString(),
                    Colors.purple,
                    Icons.trending_up,
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 2,
                  child: _buildStatCard(
                    'Resolved',
                    resolvedCount.toString(),
                    Colors.green,
                    Icons.check_circle,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
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
                            Icon(
                              Icons.error_outline,
                              size: 60,
                              color: Colors.red[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red[600]),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchIssues,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
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
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.bug_report_outlined,
                                    size: 60,
                                    color: Colors.green[400],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No issues found',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + to report an issue',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchIssues,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredIssues.length,
                              itemBuilder: (context, index) =>
                                  _buildIssueCard(_filteredIssues[index]),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportIssuePage(userData: widget.userData),
            ),
          );
          if (result == true) _fetchIssues();
        },
        backgroundColor: Colors.green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Report Issue',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String count,
    Color color,
    IconData icon,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => _filterIssues(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Widget _buildIssueCard(Map<String, dynamic> issue) {
    final category =
        _mapOrNull(issue['issue_categories']) ?? _mapOrNull(issue['category']);
    final priority =
        _mapOrNull(issue['issue_priorities']) ?? _mapOrNull(issue['priority']);
    final office = _mapOrNull(issue['offices']) ?? _mapOrNull(issue['office']);
    final priorityName = _priorityNameFromIssue(priority);
    final priorityColor = _getPriorityColor(priorityName);
    final priorityIcon = _getPriorityIcon(priorityName);
    final isEscalated = issue['escalated'] == true ||
        issue['status']?.toString() == 'ESCALATED';
    final escalationLevel =
        issue['escalation_level'] ?? issue['current_escalation_level'] ?? 0;
    final maxEscalationLevel = issue['max_escalation_level'] ?? 5;
    final statusColor =
        _getStatusColor(issue['status']?.toString(), isEscalated);
    final statusLabel = _getStatusLabel(
      issue['status']?.toString(),
      isEscalated,
      escalationLevel,
      maxEscalationLevel,
    );
    final createdAt = issue['created_at']?.toString();
    final attachments = issue['attachments'] as List? ?? [];
    final firstAttachment = attachments.isNotEmpty && attachments.first is Map
        ? attachments.first as Map<String, dynamic>
        : <String, dynamic>{};
    final hasAttachment = firstAttachment.isNotEmpty;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                IssueTrackingPage(issue: issue, userData: widget.userData),
          ),
        ).then((_) => _fetchIssues());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEscalated
                ? Colors.purple.withOpacity(0.5)
                : Colors.grey[200]!,
            width: isEscalated ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey[100]!,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => IssueTrackingPage(
                      issue: issue, userData: widget.userData),
                ),
              ).then((_) => _fetchIssues());
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: priorityColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: priorityColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              priorityIcon,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              priorityName.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: priorityColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: statusColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getStatusIcon(
                                  issue['status']?.toString(), isEscalated),
                              size: 12,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Material(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AiInspectorPage(
                                  issue: issue,
                                  userData: widget.userData,
                                ),
                              ),
                            ).then((_) => _fetchIssues());
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.auto_awesome,
                                    size: 12, color: Colors.green[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'AI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    issue['title']?.toString() ?? 'Untitled',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.category,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            category?['name']?.toString() ?? 'N/A',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            issue['location']?.toString() ?? 'N/A',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (hasAttachment)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getFileIcon(firstAttachment['fileType']),
                              size: 14, color: Colors.blue[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              firstAttachment['fileName'] ?? 'Attachment',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.blue[700]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (office != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isEscalated ? Colors.purple[50] : Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.business,
                            size: 14,
                            color: isEscalated
                                ? Colors.purple[700]
                                : Colors.green[700],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              office['name'] ?? 'Unknown Office',
                              style: TextStyle(
                                fontSize: 12,
                                color: isEscalated
                                    ? Colors.purple[700]
                                    : Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        _getDaysAgo(createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      const Spacer(),
                      Text(
                        'Tap to track →',
                        style:
                            TextStyle(fontSize: 11, color: Colors.green[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Filter by Status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildFilterOption(
                'All',
                'All Issues',
                Icons.all_inclusive,
                Colors.blue,
              ),
              _buildFilterOption(
                'Pending',
                'Pending',
                Icons.hourglass_empty,
                Colors.orange,
              ),
              _buildFilterOption(
                'In Progress',
                'In Progress',
                Icons.play_circle,
                Colors.blue,
              ),
              _buildFilterOption(
                'Escalated',
                'Escalated',
                Icons.trending_up,
                Colors.purple,
              ),
              _buildFilterOption(
                'Resolved',
                'Resolved',
                Icons.check_circle,
                Colors.green,
              ),
              _buildFilterOption(
                'Rejected',
                'Rejected',
                Icons.cancel,
                Colors.red,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterOption(
    String value,
    String title,
    IconData icon,
    Color color,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      trailing: _selectedFilter == value
          ? const Icon(Icons.check, color: Colors.green)
          : null,
      onTap: () {
        _filterIssues(value);
        Navigator.pop(context);
      },
    );
  }
}
