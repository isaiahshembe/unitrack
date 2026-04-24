import 'package:flutter/material.dart';

class IssueTrackingPage extends StatelessWidget {
  final Map<String, dynamic> issue;
  final Map<String, dynamic>? userData;

  const IssueTrackingPage({super.key, required this.issue, this.userData});

  @override
  Widget build(BuildContext context) {
    final category = issue['issue_categories'] as Map<String, dynamic>?;
    final priority = issue['issue_priorities'] as Map<String, dynamic>?;
    final office = issue['offices'] as Map<String, dynamic>?;
    final admin = issue['admins'] as Map<String, dynamic>?;
    final status = issue['status']?.toString() ?? 'pending';
    final escalationLevel = issue['escalation_level'] ?? 0;
    final isEscalated = issue['escalated'] == true;

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
            // Issue Title
            Text(
              issue['title']?.toString() ?? 'Untitled',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),

            // Tracking Timeline
            _buildTrackingTimeline(status, escalationLevel, isEscalated),
            const SizedBox(height: 24),

            // Issue Details Card
            _buildSectionCard(
              'Issue Details',
              Icons.info_outline,
              Colors.blue,
              [
                _buildDetailRow(
                  'Category',
                  category?['name']?.toString() ?? 'N/A',
                ),
                _buildDetailRow(
                  'Priority',
                  priority?['name']?.toString() ?? 'N/A',
                ),
                _buildDetailRow(
                  'Location',
                  issue['location']?.toString() ?? 'N/A',
                ),
                _buildDetailRow(
                  'Reported',
                  _formatDate(issue['created_at']?.toString()),
                ),
                _buildDetailRow('Status', _getStatusLabel(status)),
              ],
            ),
            const SizedBox(height: 16),

            // Assignment Card
            _buildSectionCard(
              'Assignment Details',
              Icons.business,
              Colors.green,
              [
                _buildDetailRow(
                  'Office',
                  office?['name']?.toString() ?? 'Pending Assignment',
                ),
                _buildDetailRow(
                  'Building',
                  office?['building']?.toString() ?? 'N/A',
                ),
                _buildDetailRow(
                  'Room',
                  office?['room_number']?.toString() ?? 'N/A',
                ),
                _buildDetailRow(
                  'Admin',
                  admin?['full_name']?.toString() ?? 'Not yet assigned',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description Card
            _buildSectionCard('Description', Icons.description, Colors.orange, [
              Text(
                issue['description']?.toString() ?? 'No description provided',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ]),
            const SizedBox(height: 16),

            // Escalation Info
            if (isEscalated)
              _buildSectionCard(
                'Escalation Status',
                Icons.arrow_upward,
                Colors.purple,
                [
                  _buildDetailRow('Level', 'Level $escalationLevel'),
                  _buildDetailRow(
                    'Escalated On',
                    _formatDate(issue['escalated_at']?.toString()),
                  ),
                  _buildDetailRow(
                    'Max Level',
                    'Level ${issue['max_escalation_level'] ?? 3}',
                  ),
                ],
              ),
            const SizedBox(height: 16),

            // Response/Updates (UI Only - Admin not implemented)
            _buildSectionCard('Updates & Responses', Icons.chat, Colors.teal, [
              if (status == 'pending')
                _buildUpdateItem(
                  'Issue Submitted',
                  'Your issue has been submitted and is pending review.',
                  issue['created_at']?.toString(),
                  Colors.orange,
                ),
              if (isEscalated)
                _buildUpdateItem(
                  'Issue Escalated',
                  'Your issue has been escalated to a higher office for faster resolution.',
                  issue['escalated_at']?.toString(),
                  Colors.purple,
                ),
              if (status == 'in_progress')
                _buildUpdateItem(
                  'Under Review',
                  'An administrator is currently reviewing your issue.',
                  DateTime.now()
                      .subtract(const Duration(hours: 2))
                      .toIso8601String(),
                  Colors.blue,
                ),
              if (status == 'resolved')
                _buildUpdateItem(
                  'Issue Resolved',
                  'Your issue has been resolved. Please confirm if the solution is satisfactory.',
                  DateTime.now()
                      .subtract(const Duration(days: 1))
                      .toIso8601String(),
                  Colors.green,
                ),
              // Dummy update for demo
              _buildUpdateItem(
                'Acknowledgement',
                'Your issue has been received and assigned to the appropriate office for handling.',
                DateTime.now()
                    .subtract(const Duration(hours: 5))
                    .toIso8601String(),
                Colors.grey,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingTimeline(
    String status,
    int escalationLevel,
    bool isEscalated,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          _buildTimelineStep('Submitted', true, Icons.send, Colors.blue),
          Expanded(
            child: Container(
              height: 2,
              color: _isStepComplete(status, 'submitted')
                  ? Colors.blue
                  : Colors.grey[300],
            ),
          ),
          _buildTimelineStep(
            'Reviewed',
            _isStepComplete(status, 'reviewed'),
            Icons.search,
            _isStepComplete(status, 'reviewed') ? Colors.blue : Colors.grey,
          ),
          Expanded(
            child: Container(
              height: 2,
              color: isEscalated || status == 'escalated'
                  ? Colors.purple
                  : Colors.grey[300],
            ),
          ),
          _buildTimelineStep(
            'Escalated',
            isEscalated || escalationLevel > 0,
            Icons.arrow_upward,
            isEscalated ? Colors.purple : Colors.grey,
          ),
          Expanded(
            child: Container(
              height: 2,
              color: status == 'resolved' ? Colors.green : Colors.grey[300],
            ),
          ),
          _buildTimelineStep(
            'Resolved',
            status == 'resolved',
            Icons.check_circle,
            status == 'resolved' ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep(
    String label,
    bool isComplete,
    IconData icon,
    Color color,
  ) {
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
            fontSize: 10,
            color: isComplete ? color : Colors.grey[500],
            fontWeight: isComplete ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  bool _isStepComplete(String status, String step) {
    switch (step) {
      case 'submitted':
        return true;
      case 'reviewed':
        return status == 'in_progress' ||
            status == 'escalated' ||
            status == 'resolved';
      default:
        return false;
    }
  }

  Widget _buildSectionCard(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
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
            width: 100,
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
    String title,
    String message,
    String? dateTime,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

  String _formatDate(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTime;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return 'Resolved';
      case 'in_progress':
        return 'In Progress';
      case 'pending':
        return 'Pending';
      case 'escalated':
        return 'Escalated';
      default:
        return status;
    }
  }
}
