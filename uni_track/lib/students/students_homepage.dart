import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/services/mobile_data_service.dart';
import 'package:uni_track/ai/ai_assistant_page.dart';
import 'package:uni_track/analytics/analytics.dart';
import 'package:uni_track/students/report_issues.dart';
import 'package:uni_track/students/students_issuespage.dart';
import 'package:uni_track/students/students_noticespage.dart';

class HomePage extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onNavigateToIssues;
  final VoidCallback onNavigateToNotices;

  const HomePage({
    super.key,
    required this.userData,
    required this.onNavigateToIssues,
    required this.onNavigateToNotices,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _supabase = Supabase.instance.client;
  final _data = MobileDataService();
  int _totalIssues = 0;
  int _pendingIssues = 0;
  int _resolvedIssues = 0;
  int _unreadNotices = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    try {
      final studentId = widget.userData['id'];

      final issuesResponse = await _data.getComplaints(
        studentId: studentId.toString(),
        limit: 500,
      );
      final issues = List<Map<String, dynamic>>.from(
        issuesResponse['complaints'] ?? [],
      );

      _totalIssues = issues.length;
      _pendingIssues = issues
          .where((i) =>
              i['status']?.toString().toUpperCase() == 'PENDING' ||
              i['status']?.toString().toUpperCase() == 'OPEN')
          .length;
      _resolvedIssues = issues
          .where((i) => i['status']?.toString().toUpperCase() == 'RESOLVED')
          .length;

      // Fetch notice count
      final notices = await _supabase
          .from('notices')
          .select('id')
          .eq('target_type', 'public');

      _unreadNotices = notices.length;

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentName = widget.userData['full_name'] ?? 'Student';
    final firstName = studentName.toString().split(' ').first;
    final college = widget.userData['colleges']?['name'] ?? 'N/A';
    final course = widget.userData['courses']?['name'] ?? 'N/A';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Dashboard',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: Colors.black, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade600, Colors.green.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          child: const Icon(Icons.person,
                              color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back, $firstName! 👋',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$course • $college',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.userData['student_id'] ?? '',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Quick Stats
              const Text(
                'Your Overview',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildStatCard(
                    'Total Issues',
                    _totalIssues.toString(),
                    Colors.blue,
                    Icons.inbox,
                    () => widget.onNavigateToIssues(),
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    'Pending',
                    _pendingIssues.toString(),
                    Colors.orange,
                    Icons.hourglass_empty,
                    () => widget.onNavigateToIssues(),
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    'Resolved',
                    _resolvedIssues.toString(),
                    Colors.green,
                    Icons.check_circle,
                    () => widget.onNavigateToIssues(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Quick Actions
              const Text(
                'Quick Actions',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      'Report Issue',
                      'Submit a new\nissue report',
                      Icons.bug_report,
                      Colors.deepOrange,
                      () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ReportIssuePage(userData: widget.userData),
                          ),
                        );
                        if (result == true) _fetchDashboardData();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildActionCard(
                      'My Issues',
                      'Track your\nreported issues',
                      Icons.list_alt,
                      Colors.blue,
                      () => widget.onNavigateToIssues(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      'Notices',
                      'View university\nannouncements',
                      Icons.campaign,
                      Colors.purple,
                      () => widget.onNavigateToNotices(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildActionCard(
                      'AI Assistant',
                      'Ask RAG/NLP\nrouting questions',
                      Icons.auto_awesome,
                      Colors.green,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AiAssistantPage(userData: widget.userData),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      'Analytics',
                      'View your\nissue statistics',
                      Icons.analytics,
                      Colors.teal,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AnalyticsPage(
                              userData: widget.userData,
                              isAdmin: false,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent Activity
              const Text(
                'Need Help?',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _buildHelpItem(
                      Icons.help_outline,
                      'How to report an issue',
                      'Tap the + button on the Issues page or use the Quick Action above',
                    ),
                    const Divider(),
                    _buildHelpItem(
                      Icons.track_changes,
                      'Track your issue status',
                      'Go to My Issues to see real-time updates on your reported issues',
                    ),
                    const Divider(),
                    _buildHelpItem(
                      Icons.support_agent,
                      'Need assistance?',
                      'Contact your college administrator through the issue comments',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon,
      VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color),
              ),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.green, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(description,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ]),
        ),
      ]),
    );
  }
}
