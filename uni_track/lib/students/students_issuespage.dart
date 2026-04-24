import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/students/report_issues.dart';
import 'package:uni_track/students/issue_tracking.dart';

class IssuesPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const IssuesPage({super.key, this.userData});

  @override
  State<IssuesPage> createState() => _IssuesPageState();
}

class _IssuesPageState extends State<IssuesPage> {
  final _supabase = Supabase.instance.client;
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
      final studentId = widget.userData?['id'];

      if (studentId == null) {
        throw Exception('Not logged in. Please login again.');
      }

      // Step 1: Fetch issues for this student with category & priority info
      final response = await _supabase
          .from('issues')
          .select(
            '*, issue_categories(name), issue_priorities(name, days_to_resolve)',
          )
          .eq('student_id', studentId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      // Step 2: Fetch office and admin info separately for each issue
      final List<Map<String, dynamic>> issuesWithDetails = [];

      for (var issue in response) {
        Map<String, dynamic> enriched = Map<String, dynamic>.from(issue);

        // Fetch office info if assigned
        if (issue['assigned_office_id'] != null) {
          try {
            final officeData = await _supabase
                .from('offices')
                .select('name, building, room_number, level')
                .eq('id', issue['assigned_office_id'])
                .maybeSingle();
            if (officeData != null) enriched['offices'] = officeData;
          } catch (e) {
            debugPrint('Error fetching office: $e');
          }
        }

        // Fetch admin info if assigned
        if (issue['assigned_admin_id'] != null) {
          try {
            final adminData = await _supabase
                .from('admins')
                .select('full_name, email')
                .eq('id', issue['assigned_admin_id'])
                .maybeSingle();
            if (adminData != null) enriched['admins'] = adminData;
          } catch (e) {
            debugPrint('Error fetching admin: $e');
          }
        }

        issuesWithDetails.add(enriched);
      }

      if (mounted) {
        setState(() {
          _issues = issuesWithDetails;
          _filterIssues(_selectedFilter);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching issues: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load issues. Pull to refresh.';
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

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'escalated':
        return Colors.purple;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'resolved':
        return 'RESOLVED';
      case 'in_progress':
        return 'IN PROGRESS';
      case 'pending':
        return 'PENDING';
      case 'escalated':
        return 'ESCALATED';
      case 'rejected':
        return 'REJECTED';
      default:
        return status?.toUpperCase() ?? 'PENDING';
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'resolved':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.autorenew;
      case 'pending':
        return Icons.hourglass_empty;
      case 'escalated':
        return Icons.arrow_upward;
      case 'rejected':
        return Icons.cancel;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'My Issues',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.black),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _fetchIssues,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                _buildStatCard(
                  'Total',
                  _issues.length.toString(),
                  Colors.blue,
                  Icons.bug_report,
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  'Pending',
                  _issues
                      .where((i) => i['status'] == 'pending')
                      .length
                      .toString(),
                  Colors.orange,
                  Icons.hourglass_empty,
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  'Resolved',
                  _issues
                      .where((i) => i['status'] == 'resolved')
                      .length
                      .toString(),
                  Colors.green,
                  Icons.check_circle,
                ),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                        Icon(
                          Icons.bug_report_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No issues found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
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
                      padding: const EdgeInsets.all(15),
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              count,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
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

  Widget _buildIssueCard(Map<String, dynamic> issue) {
    final category = issue['issue_categories'] as Map<String, dynamic>?;
    final priority = issue['issue_priorities'] as Map<String, dynamic>?;
    final office = issue['offices'] as Map<String, dynamic>?;
    final priorityName = priority?['name']?.toString() ?? 'N/A';
    final priorityColor = _getPriorityColor(priorityName);
    final statusColor = _getStatusColor(issue['status']?.toString());
    final isEscalated = issue['escalated'] == true;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                IssueTrackingPage(issue: issue, userData: widget.userData),
          ),
        );
      },
      child: Container(
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: priorityColor.withOpacity(0.2),
                    radius: 20,
                    child: Icon(
                      _getStatusIcon(issue['status']?.toString()),
                      color: priorityColor,
                      size: 20,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getDaysAgo(issue['created_at']?.toString()),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: statusColor.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          _getStatusLabel(issue['status']?.toString()),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                      if (isEscalated) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.purple.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            'L${issue['escalation_level']}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.category, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      category?['name']?.toString() ?? 'N/A',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      issue['location']?.toString() ?? 'N/A',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (office != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.business, size: 14, color: Colors.green[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Assigned to: ${office['name']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Tap to track →',
                  style: TextStyle(fontSize: 12, color: Colors.green[600]),
                ),
              ),
            ],
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
                Icons.autorenew,
                Colors.blue,
              ),
              _buildFilterOption(
                'Escalated',
                'Escalated',
                Icons.arrow_upward,
                Colors.purple,
              ),
              _buildFilterOption(
                'Resolved',
                'Resolved',
                Icons.check_circle,
                Colors.green,
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
