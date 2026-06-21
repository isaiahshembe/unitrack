import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uni_track/services/mobile_data_service.dart';

class AnalyticsPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  final bool isAdmin;
  const AnalyticsPage({
    super.key,
    required this.userData,
    this.isAdmin = false,
  });

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  final _data = MobileDataService();
  late TabController _tabController;

  bool _isLoading = true;
  int _totalIssues = 0;
  int _resolvedCount = 0;
  int _pendingCount = 0;
  int _escalatedCount = 0;
  int _rejectedCount = 0;
  int _inProgressCount = 0;
  int _resolutionRate = 0;
  int _responseRate = 0;
  String _avgResolutionDays = '0';
  String _avgResponseDays = '0';
  Map<String, int> _priorityBreakdown = {};
  List<Map<String, dynamic>> _monthlyData = [];
  List<Map<String, dynamic>> _categoryData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAnalytics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalytics() async {
    setState(() => _isLoading = true);

    try {
      if (widget.isAdmin) {
        await _fetchAdminAnalytics();
      } else {
        await _fetchStudentAnalytics();
      }
    } catch (e) {}

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchStudentAnalytics() async {
    final studentId = widget.userData['id'];

    final response = await _data.getComplaints(
      studentId: studentId.toString(),
      limit: 500,
    );

    final List<Map<String, dynamic>> issueList =
        List<Map<String, dynamic>>.from(response['complaints'] ?? []);

    _totalIssues = issueList.length;
    _resolvedCount = issueList
        .where((i) => i['status']?.toString().toUpperCase() == 'RESOLVED')
        .length;
    _pendingCount = issueList
        .where((i) =>
            i['status']?.toString().toUpperCase() == 'PENDING' ||
            i['status']?.toString().toUpperCase() == 'OPEN')
        .length;
    _escalatedCount = issueList.where((i) => i['escalated'] == true).length;
    _rejectedCount = issueList
        .where((i) => i['status']?.toString().toUpperCase() == 'REJECTED')
        .length;
    _inProgressCount = issueList
        .where((i) =>
            i['status']?.toString().toUpperCase() == 'IN_PROGRESS' ||
            i['status']?.toString().toUpperCase() == 'UNDER_REVIEW')
        .length;

    _resolutionRate =
        _totalIssues > 0 ? (_resolvedCount / _totalIssues * 100).round() : 0;

    // Average resolution time
    final resolvedIssues = issueList
        .where((i) => i['status']?.toString().toUpperCase() == 'RESOLVED')
        .toList();
    double avgDays = 0;
    if (resolvedIssues.isNotEmpty) {
      for (var issue in resolvedIssues) {
        if (issue['created_at'] != null && issue['updated_at'] != null) {
          final created = DateTime.parse(issue['created_at'].toString());
          final resolved2 = DateTime.parse(issue['updated_at'].toString());
          avgDays += resolved2.difference(created).inHours / 24;
        }
      }
      avgDays = avgDays / resolvedIssues.length;
    }
    _avgResolutionDays = avgDays.toStringAsFixed(1);

    // Priority breakdown
    final Map<String, int> priorityMap = {};
    for (var issue in issueList) {
      final p = issue['priority']?['name']?.toString() ??
          issue['issue_priorities']?['name']?.toString() ??
          'Unknown';
      priorityMap[p] = (priorityMap[p] ?? 0) + 1;
    }
    _priorityBreakdown = priorityMap;

    // Category breakdown
    final Map<String, int> categoryMap = {};
    for (var issue in issueList) {
      final cat = issue['category']?['name']?.toString() ??
          issue['issue_categories']?['name']?.toString() ??
          'Other';
      categoryMap[cat] = (categoryMap[cat] ?? 0) + 1;
    }
    _categoryData = categoryMap.entries
        .map((e) => {'name': e.key, 'count': e.value})
        .toList();

    // Monthly breakdown
    final Map<String, Map<String, dynamic>> monthMap = {};
    for (var issue in issueList) {
      if (issue['created_at'] != null) {
        final date = DateTime.parse(issue['created_at'].toString());
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        if (!monthMap.containsKey(key)) {
          monthMap[key] = {
            'month': key,
            'monthName': _getMonthName(date.month),
            'total': 0,
            'resolved': 0,
          };
        }
        monthMap[key]!['total'] = (monthMap[key]!['total'] ?? 0) + 1;
        if (issue['status']?.toString().toUpperCase() == 'RESOLVED') {
          monthMap[key]!['resolved'] = (monthMap[key]!['resolved'] ?? 0) + 1;
        }
      }
    }
    _monthlyData = monthMap.values.toList()
      ..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
  }

  Future<void> _fetchAdminAnalytics() async {
    final response = await _data.getAdminComplaints(
      limit: 500,
      adminData: widget.userData,
    );

    final List<Map<String, dynamic>> issueList =
        List<Map<String, dynamic>>.from(response['complaints'] ?? []);

    _totalIssues = issueList.length;
    _resolvedCount = issueList
        .where((i) => i['status']?.toString().toUpperCase() == 'RESOLVED')
        .length;
    _pendingCount = issueList
        .where((i) =>
            i['status']?.toString().toUpperCase() == 'PENDING' ||
            i['status']?.toString().toUpperCase() == 'OPEN')
        .length;
    _escalatedCount = issueList.where((i) => i['escalated'] == true).length;
    _rejectedCount = issueList
        .where((i) => i['status']?.toString().toUpperCase() == 'REJECTED')
        .length;
    _inProgressCount = issueList
        .where((i) =>
            i['status']?.toString().toUpperCase() == 'IN_PROGRESS' ||
            i['status']?.toString().toUpperCase() == 'UNDER_REVIEW')
        .length;

    _responseRate = _totalIssues > 0
        ? (((_resolvedCount + _rejectedCount + _inProgressCount) /
                _totalIssues *
                100))
            .round()
        : 0;

    // Average response time
    final respondedIssues = issueList
        .where((i) =>
            i['status']?.toString().toUpperCase() != 'PENDING' &&
            i['status']?.toString().toUpperCase() != 'OPEN')
        .toList();
    double avgResponse = 0;
    if (respondedIssues.isNotEmpty) {
      for (var issue in respondedIssues) {
        if (issue['created_at'] != null && issue['updated_at'] != null) {
          final created = DateTime.parse(issue['created_at'].toString());
          final updated = DateTime.parse(issue['updated_at'].toString());
          avgResponse += updated.difference(created).inHours / 24;
        }
      }
      avgResponse = avgResponse / respondedIssues.length;
    }
    _avgResponseDays = avgResponse.toStringAsFixed(1);

    // Category breakdown
    final Map<String, int> categoryMap = {};
    for (var issue in issueList) {
      final cat = issue['category']?['name']?.toString() ??
          issue['issue_categories']?['name']?.toString() ??
          'Other';
      categoryMap[cat] = (categoryMap[cat] ?? 0) + 1;
    }
    _categoryData = categoryMap.entries
        .map((e) => {'name': e.key, 'count': e.value})
        .toList();

    // Monthly breakdown
    final Map<String, Map<String, dynamic>> monthMap = {};
    for (var issue in issueList) {
      if (issue['created_at'] != null) {
        final date = DateTime.parse(issue['created_at'].toString());
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        if (!monthMap.containsKey(key)) {
          monthMap[key] = {
            'month': key,
            'monthName': _getMonthName(date.month),
            'total': 0,
            'resolved': 0,
          };
        }
        monthMap[key]!['total'] = (monthMap[key]!['total'] ?? 0) + 1;
        if (issue['status']?.toString().toUpperCase() == 'RESOLVED') {
          monthMap[key]!['resolved'] = (monthMap[key]!['resolved'] ?? 0) + 1;
        }
      }
    }
    _monthlyData = monthMap.values.toList()
      ..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Analytics',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _fetchAnalytics,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.green,
          labelColor: Colors.green,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard, size: 18)),
            Tab(text: 'Trends', icon: Icon(Icons.trending_up, size: 18)),
            Tab(text: 'Categories', icon: Icon(Icons.pie_chart, size: 18)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildTrendsTab(),
                _buildCategoriesTab(),
              ],
            ),
    );
  }

  // ==================== TAB 1: OVERVIEW ====================
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards Grid - Fixed overflow
          _buildKpiGrid(),
          const SizedBox(height: 20),

          // Main Metric Card
          _buildMainMetricCard(),
          const SizedBox(height: 20),

          // Status Distribution
          _buildStatusDistribution(),
          const SizedBox(height: 20),

          // Priority Breakdown (student only)
          if (!widget.isAdmin && _priorityBreakdown.isNotEmpty) ...[
            _buildPriorityBreakdown(),
            const SizedBox(height: 20),
          ],

          // Average Time Card
          _buildInfoCard(
            Icons.timer,
            widget.isAdmin ? 'Avg Response Time' : 'Avg Resolution Time',
            '${widget.isAdmin ? _avgResponseDays : _avgResolutionDays} days',
            Colors.indigo,
          ),
          const SizedBox(height: 20), // Extra padding at bottom
        ],
      ),
    );
  }

  // ==================== TAB 2: TRENDS ====================
  Widget _buildTrendsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Monthly Trends'),
          const SizedBox(height: 12),
          if (_monthlyData.isNotEmpty)
            _buildMonthlyChart()
          else
            _buildEmptyState('No monthly data available yet'),
          const SizedBox(height: 20),
          _buildSectionTitle('Performance Metrics'),
          const SizedBox(height: 12),
          _buildPerformanceMetrics(),
          const SizedBox(height: 20), // Extra padding at bottom
        ],
      ),
    );
  }

  // ==================== TAB 3: CATEGORIES ====================
  Widget _buildCategoriesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Issues by Category'),
          const SizedBox(height: 12),
          if (_categoryData.isNotEmpty)
            _buildCategoryChart() // Single comprehensive chart
          else
            _buildEmptyState('No category data yet'),
          const SizedBox(height: 20), // Extra padding at bottom
        ],
      ),
    );
  }

  // ==================== WIDGET BUILDERS ====================

  Widget _buildKpiGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _buildKpiCard(
          'Total',
          _totalIssues.toString(),
          Colors.blue,
          Icons.inbox,
          'All time',
        ),
        _buildKpiCard(
          'Resolved',
          _resolvedCount.toString(),
          Colors.green,
          Icons.check_circle,
          '${_resolutionRate}%',
        ),
        _buildKpiCard(
          'Pending',
          _pendingCount.toString(),
          Colors.orange,
          Icons.hourglass_empty,
          'Active',
        ),
        _buildKpiCard(
          'Escalated',
          _escalatedCount.toString(),
          Colors.purple,
          Icons.arrow_upward,
          'L1-L3',
        ),
      ],
    );
  }

  Widget _buildKpiCard(
    String label,
    String value,
    Color color,
    IconData icon,
    String subtitle,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
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
          ],
        ),
      ),
    );
  }

  Widget _buildMainMetricCard() {
    final rate = widget.isAdmin ? _responseRate : _resolutionRate;
    final title = widget.isAdmin ? 'Response Rate' : 'Resolution Rate';
    final subtitle =
        widget.isAdmin ? 'of issues responded to' : 'of issues resolved';
    final icon = widget.isAdmin ? Icons.speed : Icons.check_circle_outline;
    final color = widget.isAdmin ? Colors.teal : Colors.green;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$rate%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
              Icon(icon, color: Colors.white, size: 48),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: rate / 100,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDistribution() {
    final items = [
      {'label': 'Resolved', 'count': _resolvedCount, 'color': Colors.green},
      {'label': 'In Progress', 'count': _inProgressCount, 'color': Colors.blue},
      {'label': 'Pending', 'count': _pendingCount, 'color': Colors.orange},
      {'label': 'Escalated', 'count': _escalatedCount, 'color': Colors.purple},
      {'label': 'Rejected', 'count': _rejectedCount, 'color': Colors.red},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey[100]!, blurRadius: 8)],
      ),
      child: Column(
        children: items.map((item) {
          final count = item['count'] as int;
          final percentage =
              _totalIssues > 0 ? (count / _totalIssues * 100).round() : 0;
          final color = item['color'] as Color;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item['label'] as String,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      '$count ($percentage%)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Colors.grey[100],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriorityBreakdown() {
    final colors = {
      'Low': Colors.green,
      'Medium': Colors.orange,
      'High': Colors.deepOrange,
      'Critical': Colors.red,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey[100]!, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Priority Distribution',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ..._priorityBreakdown.entries.map((entry) {
            final color = colors[entry.key] ?? Colors.grey;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(_getPriorityIcon(entry.key), color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                        Text(entry.key, style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    entry.value.toString(),
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart() {
    final maxTotal = _monthlyData.fold<int>(
      0,
      (max, item) =>
          (item['total'] as int) > max ? (item['total'] as int) : max,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey[100]!, blurRadius: 8)],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _monthlyData.map((data) {
                final total = (data['total'] as int).toDouble();
                final height = maxTotal > 0 ? (total / maxTotal * 150) : 0.0;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          data['total'].toString(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: max(4, height),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[300]!, Colors.green[600]!],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data['monthName'] as String,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart() {
    final maxCount = _categoryData.fold<int>(
      0,
      (max, item) =>
          (item['count'] as int) > max ? (item['count'] as int) : max,
    );

    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.red,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey[100]!, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chart Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Category',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Text(
                'Count',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Categories List
          ...List.generate(_categoryData.length, (index) {
            final cat = _categoryData[index];
            final count = cat['count'] as int;
            final color = colors[index % colors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat['name'] as String,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          count.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxCount > 0 ? count / maxCount : 0,
                      backgroundColor: Colors.grey[100],
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPerformanceMetrics() {
    final escalationRate =
        _totalIssues > 0 ? (_escalatedCount / _totalIssues * 100).round() : 0;

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
            'Efficiency Score',
            '${widget.isAdmin ? _responseRate : _resolutionRate}%',
            Icons.auto_graph,
            Colors.green,
          ),
          const Divider(),
          _buildMetricRow(
            'Avg Response Time',
            '${widget.isAdmin ? _avgResponseDays : _avgResolutionDays} days',
            Icons.schedule,
            Colors.blue,
          ),
          const Divider(),
          _buildMetricRow(
            'Active Issues',
            _pendingCount.toString(),
            Icons.warning_amber,
            Colors.orange,
          ),
          const Divider(),
          _buildMetricRow(
            'Escalation Rate',
            '$escalationRate%',
            Icons.trending_up,
            Colors.purple,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String title,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey[100]!, blurRadius: 8)],
      ),
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
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
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

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.grey[500], fontSize: 14),
        ),
      ),
    );
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'Low':
        return Icons.arrow_downward;
      case 'Medium':
        return Icons.remove;
      case 'High':
        return Icons.arrow_upward;
      case 'Critical':
        return Icons.warning;
      default:
        return Icons.help;
    }
  }
}
