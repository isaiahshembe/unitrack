import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminIssuespage extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminIssuespage({super.key, required this.adminData});

  @override
  State<AdminIssuespage> createState() => _AdminIssuespageState();
}

class _AdminIssuespageState extends State<AdminIssuespage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _filteredIssues = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';

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
      // Fetch issues assigned to this admin
      final response = await _supabase
          .from('issues')
          .select('*, issue_categories(name), issue_priorities(name, days_to_resolve)')
          .eq('assigned_admin_id', widget.adminData['id'])
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      // Fetch office info for each issue
      final List<Map<String, dynamic>> enrichedIssues = [];
      for (var issue in response) {
        Map<String, dynamic> enriched = Map<String, dynamic>.from(issue);
        
        if (issue['assigned_office_id'] != null) {
          final officeData = await _supabase
              .from('offices')
              .select('name, building, room_number, level')
              .eq('id', issue['assigned_office_id'])
              .maybeSingle();
          enriched['offices'] = officeData;
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load issues: $e';
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
            .where((i) => i['status']?.toString().toLowerCase() == filter.toLowerCase())
            .toList();
      }
    });
  }

  Future<void> _updateIssueStatus(String issueId, String newStatus) async {
    try {
      await _supabase
          .from('issues')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', issueId);

      _showSnackBar('Status updated to: $newStatus', Colors.green);
      _fetchAssignedIssues();
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _resolveIssue(String issueId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Issue', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Mark this issue as resolved?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'resolved': return Colors.green;
      case 'in_progress': return Colors.blue;
      case 'pending': return Colors.orange;
      case 'escalated': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _getPriorityColor(String? name) {
    switch (name?.toLowerCase()) {
      case 'low': return Colors.green;
      case 'medium': return Colors.orange;
      case 'high': return Colors.deepOrange;
      case 'critical': return Colors.red;
      default: return Colors.grey;
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Assigned Issues', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 20)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.black), onPressed: _fetchAssignedIssues),
        ],
      ),
      body: Column(
        children: [
          // Stats
          Container(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                _buildStatCard('Total', _issues.length.toString(), Colors.blue, Icons.inbox),
                const SizedBox(width: 10),
                _buildStatCard('Pending', _issues.where((i) => i['status'] == 'pending').length.toString(), Colors.orange, Icons.hourglass_empty),
                const SizedBox(width: 10),
                _buildStatCard('Resolved', _issues.where((i) => i['status'] == 'resolved').length.toString(), Colors.green, Icons.check_circle),
              ],
            ),
          ),
          // Filters
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
                  _buildFilterChip('Escalated'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Resolved'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.green)))
                : _errorMessage != null
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(_errorMessage!, style: TextStyle(color: Colors.red[600])),
                        ElevatedButton(onPressed: _fetchAssignedIssues, child: const Text('Retry')),
                      ]))
                    : _filteredIssues.isEmpty
                        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No issues assigned', style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                          ]))
                        : RefreshIndicator(
                            onRefresh: _fetchAssignedIssues,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(15),
                              itemCount: _filteredIssues.length,
                              itemBuilder: (context, index) => _buildIssueCard(_filteredIssues[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final selected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => _filterIssues(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: selected ? Colors.green : Colors.grey[100], borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? Colors.green : Colors.grey[300]!)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? Colors.white : Colors.grey[700])),
      ),
    );
  }

  Widget _buildIssueCard(Map<String, dynamic> issue) {
    final category = issue['issue_categories'] as Map<String, dynamic>?;
    final priority = issue['issue_priorities'] as Map<String, dynamic>?;
    final priorityName = priority?['name']?.toString() ?? 'N/A';
    final priorityColor = _getPriorityColor(priorityName);
    final status = issue['status']?.toString() ?? 'pending';
    final statusColor = _getStatusColor(status);
    final isEscalated = issue['escalated'] == true;
    final studentName = issue['student_name']?.toString() ?? 'Unknown';
    final studentEmail = issue['student_email']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[200]!)),
      child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: priorityColor.withOpacity(0.2), child: Icon(Icons.warning_amber, color: priorityColor, size: 20)),
        title: Text(issue['title']?.toString() ?? 'Untitled', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(children: [
              _buildBadge(status.toUpperCase(), statusColor),
              const SizedBox(width: 6),
              _buildBadge(priorityName.toUpperCase(), priorityColor),
              if (isEscalated) ...[const SizedBox(width: 6), _buildBadge('ESCALATED', Colors.purple)],
            ]),
            const SizedBox(height: 4),
            Text('$studentName • ${_getDaysAgo(issue['created_at']?.toString())}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Category', category?['name']?.toString() ?? 'N/A'),
                      _buildDetailRow('Location', issue['location']?.toString() ?? 'N/A'),
                      _buildDetailRow('Priority', priorityName),
                      _buildDetailRow('Reported', _formatDate(issue['created_at']?.toString())),
                      _buildDetailRow('Student', studentName),
                      _buildDetailRow('Email', studentEmail),
                      if (issue['student_phone'] != null)
                        _buildDetailRow('Phone', issue['student_phone'].toString()),
                      const Divider(),
                      const Text('Description:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(issue['description']?.toString() ?? 'No description', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Action Buttons
                Row(
                  children: [
                    if (status == 'pending')
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _updateIssueStatus(issue['id'].toString(), 'in_progress'),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Start'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      ),
                    if (status == 'in_progress') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _resolveIssue(issue['id'].toString()),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Resolve'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      ),
                    ],
                    if (status != 'resolved') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showRejectDialog(issue['id'].toString()),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: Colors.black87))),
        ],
      ),
    );
  }

  Future<void> _showRejectDialog(String issueId) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Issue', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Reason for rejection...', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == true) {
      await _updateIssueStatus(issueId, 'rejected');
    }
  }
}