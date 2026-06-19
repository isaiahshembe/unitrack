import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/ai/ai_operations_page.dart';
import 'package:uni_track/analytics/analytics.dart';
import 'package:uni_track/services/mobile_data_service.dart';

class AdminHomepage extends StatefulWidget {
  final Map<String, dynamic> adminData;
  final VoidCallback onNavigateToIssues;
  final VoidCallback onNavigateToNotices;

  const AdminHomepage({
    super.key,
    required this.adminData,
    required this.onNavigateToIssues,
    required this.onNavigateToNotices,
  });

  @override
  State<AdminHomepage> createState() => _AdminHomepageState();
}

class _AdminHomepageState extends State<AdminHomepage> {
  final _supabase = Supabase.instance.client;
  final _data = MobileDataService();
  int _totalAssigned = 0;
  int _pendingIssues = 0;
  int _resolvedToday = 0;
  int _escalatedCount = 0;
  String _officeName = '';
  String _officeLevel = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final issuesResponse = await _data.getAdminComplaints(
        status: 'All',
        limit: 500,
        adminData: widget.adminData,
      );
      final issues = List<Map<String, dynamic>>.from(
        issuesResponse['complaints'] ?? [],
      );

      _totalAssigned = issues.length;
      _pendingIssues = issues
          .where((i) =>
              i['status']?.toString().toUpperCase() == 'PENDING' ||
              i['status']?.toString().toUpperCase() == 'OPEN')
          .length;
      _escalatedCount = issues.where((i) => i['escalated'] == true).length;

      final today = DateTime.now();
      _resolvedToday = issues.where((i) {
        if (i['status']?.toString().toUpperCase() == 'RESOLVED' &&
            i['updated_at'] != null) {
          final updated = DateTime.parse(i['updated_at'].toString());
          return updated.year == today.year &&
              updated.month == today.month &&
              updated.day == today.day;
        }
        return false;
      }).length;

      final assignedOfficeId = _toInt(widget.adminData['assigned_office_id'] ??
          widget.adminData['office_id']);
      if (assignedOfficeId != null) {
        final office = await _supabase
            .from('offices')
            .select('name, level')
            .eq('id', assignedOfficeId)
            .maybeSingle();

        if (office != null) {
          _officeName = office['name'] ?? '';
          _officeLevel = office['level'] ?? '';
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading dashboard: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final adminName = widget.adminData['full_name'] ?? 'Admin';
    final firstName = adminName.toString().split(' ').first;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Dashboard',
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
            onPressed: _fetchDashboardData,
            tooltip: 'Refresh Dashboard',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        color: Colors.green,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Welcome Card
                  _buildWelcomeCard(firstName),
                  const SizedBox(height: 20),

                  // KPI Grid
                  _buildSectionTitle('Issue Overview'),
                  const SizedBox(height: 12),
                  _buildKpiGrid(),
                  const SizedBox(height: 24),

                  // Quick Actions
                  _buildSectionTitle('Quick Actions'),
                  const SizedBox(height: 12),
                  _buildQuickActionsGrid(),
                  const SizedBox(height: 24),

                  // Performance Snapshot
                  _buildSectionTitle('Performance Snapshot'),
                  const SizedBox(height: 12),
                  _buildPerformanceSnapshot(),
                  const SizedBox(height: 24),

                  // Pro Tip
                  _buildProTip(),
                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }

  Widget _buildWelcomeCard(String firstName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
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
                radius: 26,
                backgroundColor: Colors.white.withOpacity(0.3),
                child: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $firstName! 👋',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_officeName • $_officeLevel',
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.badge, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text(
                  widget.adminData['employee_id'] ?? 'Admin',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.3,
      children: [
        _buildKpiCard(
          'Total Assigned',
          _totalAssigned.toString(),
          Colors.blue,
          Icons.inbox,
        ),
        _buildKpiCard(
          'Pending',
          _pendingIssues.toString(),
          Colors.orange,
          Icons.hourglass_empty,
        ),
        _buildKpiCard(
          'Resolved Today',
          _resolvedToday.toString(),
          Colors.green,
          Icons.check_circle,
        ),
        _buildKpiCard(
          'Escalated',
          _escalatedCount.toString(),
          Colors.purple,
          Icons.arrow_upward,
        ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, Color color, IconData icon) {
    return GestureDetector(
      onTap: () {
        widget.onNavigateToIssues();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        _buildActionCard(
          'View Issues',
          'Manage assigned tickets',
          Icons.list_alt,
          Colors.blue,
          () => widget.onNavigateToIssues(),
        ),
        _buildActionCard(
          'Send Notice',
          'Create announcement',
          Icons.campaign,
          Colors.purple,
          () => widget.onNavigateToNotices(),
        ),
        _buildActionCard(
          'AI Ops',
          'Run AI engine tasks',
          Icons.auto_awesome,
          Colors.green,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiOperationsPage(userData: widget.adminData),
              ),
            );
          },
        ),
        _buildActionCard(
          'Analytics',
          'View statistics',
          Icons.analytics,
          Colors.teal,
          () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AnalyticsPage(
                  userData: widget.adminData,
                  isAdmin: true,
                ),
              ),
            );
            // Refresh data if coming back from analytics
            if (result == true) {
              _fetchDashboardData();
            }
          },
        ),
        _buildActionCard(
          'Refresh',
          'Reload data',
          Icons.refresh,
          Colors.green,
          () => _fetchDashboardData(),
        ),
      ],
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceSnapshot() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey[100]!, blurRadius: 8)],
      ),
      child: Column(
        children: [
          _buildMetricRow(
            'Issues Resolved Today',
            '$_resolvedToday',
            Icons.today,
            Colors.green,
          ),
          const Divider(),
          _buildMetricRow(
            'Pending Review',
            '$_pendingIssues',
            Icons.pending_actions,
            Colors.orange,
          ),
          const Divider(),
          _buildMetricRow(
            'Escalated Issues',
            '$_escalatedCount',
            Icons.arrow_upward,
            Colors.purple,
          ),
          const Divider(),
          _buildMetricRow(
            'Total Assigned',
            '$_totalAssigned',
            Icons.inbox,
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return GestureDetector(
      onTap: () {
        widget.onNavigateToIssues();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProTip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb, color: Colors.green[700], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pro Tip',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[900],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Respond to issues quickly to maintain a high response rate. Issues not resolved within their timeframe will auto-escalate.',
                  style: TextStyle(fontSize: 10, color: Colors.green[800]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}
