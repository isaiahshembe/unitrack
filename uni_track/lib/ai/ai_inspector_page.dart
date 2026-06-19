import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uni_track/services/mobile_data_service.dart';

class AiInspectorPage extends StatefulWidget {
  final Map<String, dynamic> issue;
  final Map<String, dynamic>? userData;

  const AiInspectorPage({
    super.key,
    required this.issue,
    this.userData,
  });

  @override
  State<AiInspectorPage> createState() => _AiInspectorPageState();
}

class _AiInspectorPageState extends State<AiInspectorPage> {
  final _mobileData = MobileDataService();
  bool _isLoading = true;
  bool _isRunning = false;
  String? _error;
  Map<String, dynamic>? _data;

  String get _complaintId => widget.issue['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_complaintId.isEmpty) {
      setState(() {
        _error = 'Missing complaint id';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _mobileData.getAiInspect(_complaintId);
      if (mounted) {
        setState(() {
          _data = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _runAction(String action, String label) async {
    setState(() => _isRunning = true);
    try {
      final response = action == 'run-agent' || action == 'force-escalate'
          ? await _mobileData.patchComplaintAction(
              complaintId: _complaintId, action: action)
          : await _mobileData.postAiInspect(
              complaintId: _complaintId, action: action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label completed'),
            backgroundColor: Colors.green,
          ),
        );
        _data = response;
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complaint = _data?['complaint'] as Map<String, dynamic>?;
    final ai = _data?['ai'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('AI Inspection'),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.green),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _error != null
              ? _buildError(_error!)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(complaint),
                      const SizedBox(height: 16),
                      _buildActionRow(ai),
                      const SizedBox(height: 16),
                      _buildNlpCard(ai),
                      const SizedBox(height: 12),
                      _buildRagCard(ai),
                      const SizedBox(height: 12),
                      _buildEscalationCard(ai),
                      const SizedBox(height: 12),
                      _buildSlaCard(ai),
                      const SizedBox(height: 12),
                      _buildSimilarityCard(ai),
                      const SizedBox(height: 12),
                      _buildAttachmentsCard(complaint),
                      const SizedBox(height: 12),
                      _buildStoredNlpCard(ai),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'AI inspection could not be loaded',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic>? complaint) {
    final category = complaint?['category'] as Map<String, dynamic>?;
    final office = complaint?['office'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xff1b5e20), Color(0xff43a047)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            complaint?['title']?.toString() ?? 'Untitled issue',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(complaint?['trackingCode']?.toString() ?? 'No code',
                  Icons.tag),
              _badge(complaint?['status']?.toString() ?? 'N/A', Icons.history),
              _badge(complaint?['priority']?.toString() ?? 'N/A',
                  Icons.priority_high),
              _badge(category?['name']?.toString() ?? 'N/A', Icons.category),
              if (office != null)
                _badge(
                    office['name']?.toString() ?? 'Unassigned', Icons.business),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(Map<String, dynamic>? ai) {
    final hasAi = ai != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Actions',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton('Refresh Analysis', Icons.refresh, Colors.green,
                  () => _load()),
              if (hasAi)
                _actionButton('Reclassify', Icons.class_, Colors.blue,
                    () => _runAction('reclassify', 'Reclassification')),
              if (hasAi)
                _actionButton('Adjust SLA', Icons.timer, Colors.orange,
                    () => _runAction('adjust-sla', 'SLA adjustment')),
              _actionButton('Run Agent', Icons.auto_awesome, Colors.purple,
                  () => _runAction('run-agent', 'AI agent')),
              _actionButton('Force Escalate', Icons.arrow_upward, Colors.red,
                  () => _runAction('force-escalate', 'Escalation')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _isRunning ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNlpCard(Map<String, dynamic>? ai) {
    final nlp = ai?['nlpAnalysis'] as Map<String, dynamic>?;
    if (nlp == null || nlp['error'] != null) {
      return _messageCard(
          'NLP Classification', 'Classification unavailable', Colors.orange);
    }

    final textStats = nlp['textStats'] as Map<String, dynamic>?;
    final keywords = _stringList(nlp['keywordMatches']);

    return _sectionCard(
      'NLP Classification',
      Icons.psychology,
      Colors.blue,
      [
        _detail('Method', _methodLabel(nlp['method']?.toString())),
        _detail('Category', nlp['category']?.toString() ?? 'N/A'),
        _detail('Confidence', _percent(nlp['confidence'])),
        _detail('Urgency', _percent(nlp['sentimentUrgency'])),
        if (textStats != null)
          _detail('Tokens', '${textStats['totalTokens'] ?? 0} total'),
        if (keywords.isNotEmpty) _list('Matched Keywords', keywords),
      ],
    );
  }

  Widget _buildRagCard(Map<String, dynamic>? ai) {
    final rag = ai?['ragRouting'] as Map<String, dynamic>?;
    if (rag == null)
      return _messageCard('RAG Routing', 'Routing unavailable', Colors.orange);

    return _sectionCard(
      'RAG Routing',
      Icons.route,
      Colors.green,
      [
        _detail(
            'Routed Office',
            rag['officeName']?.toString() ??
                rag['suggestedOfficeName']?.toString() ??
                'N/A'),
        _detail('Confidence', _percent(rag['confidence'])),
        if (rag['categoryId'] != null)
          _detail('Category ID', rag['categoryId'].toString()),
        if (rag['suggestedOfficeId'] != null)
          _detail('Office ID', rag['suggestedOfficeId'].toString()),
        _detail('Reasoning',
            rag['reasoning']?.toString() ?? 'No reasoning available'),
        if (rag['topMatch'] != null)
          _detail('Top Match', rag['topMatch'].toString()),
        if (rag['usedFallback'] == true) _detail('Fallback Used', 'Yes'),
      ],
    );
  }

  Widget _buildEscalationCard(Map<String, dynamic>? ai) {
    final escalation = ai?['escalationEvaluation'] as Map<String, dynamic>?;
    if (escalation == null)
      return _messageCard(
          'Escalation Evaluation', 'Evaluation unavailable', Colors.orange);

    final factors = _stringList(escalation['factors']);

    return _sectionCard(
      'Escalation Evaluation',
      Icons.trending_up,
      Colors.purple,
      [
        _detail('Should Escalate',
            escalation['shouldEscalate'] == true ? 'Yes' : 'No'),
        _detail('Urgency Score', _percent(escalation['urgencyScore'])),
        _detail('Current Office',
            escalation['currentOfficeName']?.toString() ?? 'N/A'),
        _detail('Reason',
            escalation['reason']?.toString() ?? 'No reason available'),
        if (factors.isNotEmpty) _list('Factors', factors),
      ],
    );
  }

  Widget _buildSlaCard(Map<String, dynamic>? ai) {
    final sla = ai?['sla'] as Map<String, dynamic>?;
    if (sla == null)
      return _messageCard(
          'SLA Prediction', 'Prediction unavailable', Colors.orange);

    final prediction = sla['prediction'] as Map<String, dynamic>?;
    final historicalAvg = sla['historicalAvg'];
    final adjusted = sla['autoAdjusted'] as Map<String, dynamic>?;

    return _sectionCard(
      'SLA Prediction',
      Icons.timer,
      Colors.orange,
      [
        _detail('Predicted Days',
            prediction?['predictedDays']?.toString() ?? 'N/A'),
        _detail('Prediction Confidence', _percent(prediction?['confidence'])),
        _detail(
            'Historical Average',
            historicalAvg == null
                ? 'N/A'
                : '${historicalAvg.toStringAsFixed(1)} days'),
        if (adjusted != null) ...[
          _detail(
              'Adjusted Days', adjusted['adjustedDays']?.toString() ?? 'N/A'),
          _detail('Adjusted Deadline',
              _formatDate(adjusted['adjustedDeadline']?.toString())),
          _detail('Adjustment Rationale',
              adjusted['rationale']?.toString() ?? 'N/A'),
        ],
        if (prediction?['factors'] != null)
          _list('SLA Factors', _stringList(prediction!['factors'])),
      ],
    );
  }

  Widget _buildSimilarityCard(Map<String, dynamic>? ai) {
    final similarity = ai?['similarity'] as Map<String, dynamic>?;
    if (similarity == null)
      return _messageCard(
          'Similarity Checks', 'Similarity checks unavailable', Colors.orange);

    final similar =
        List<Map<String, dynamic>>.from(similarity['similarComplaints'] ?? []);
    final duplicates =
        List<Map<String, dynamic>>.from(similarity['duplicates'] ?? []);
    final anomaly = similarity['anomaly'] as Map<String, dynamic>?;

    return _sectionCard(
      'Similarity & Anomaly',
      Icons.auto_awesome,
      Colors.teal,
      [
        _detail('Similar Complaints', '${similar.length} found'),
        _detail('Possible Duplicates', '${duplicates.length} found'),
        if (anomaly != null) ...[
          _detail('Anomaly', anomaly['isAnomaly'] == true ? 'Yes' : 'No'),
          _detail(
              'Current Volume', anomaly['currentVolume']?.toString() ?? 'N/A'),
          _detail(
              'Baseline Average', anomaly['baselineAvg']?.toString() ?? 'N/A'),
          _detail('Message', anomaly['message']?.toString() ?? 'N/A'),
        ],
        if (similar.isNotEmpty) _complaintList('Similar Complaints', similar),
        if (duplicates.isNotEmpty)
          _complaintList('Possible Duplicates', duplicates),
      ],
    );
  }

  Widget _buildAttachmentsCard(Map<String, dynamic>? complaint) {
    final attachments =
        List<Map<String, dynamic>>.from(complaint?['attachments'] ?? []);

    return _sectionCard(
      'Attachments',
      Icons.attach_file,
      Colors.blue,
      attachments.isEmpty
          ? [const Text('No attachments indexed for this complaint.')]
          : attachments
              .map(
                (attachment) => _detail(
                  attachment['fileName']?.toString() ?? 'Attachment',
                  '${attachment['fileType'] ?? 'unknown'} • ${attachment['extractedTextLength'] ?? 0} chars extracted',
                ),
              )
              .toList(),
    );
  }

  Widget _buildStoredNlpCard(Map<String, dynamic>? ai) {
    final stored = ai?['storedNlpResults'];
    if (stored == null) return const SizedBox.shrink();

    return _sectionCard(
      'Stored NLP Results',
      Icons.storage,
      Colors.grey,
      [
        _jsonPreview(jsonEncode(stored)),
      ],
    );
  }

  Widget _sectionCard(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _messageCard(String title, String message, Color color) {
    return _sectionCard(title, Icons.info_outline, color, [Text(message)]);
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _list(String label, List<String> values) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: values
                .map((value) =>
                    Chip(label: Text(value), padding: EdgeInsets.zero))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _complaintList(String label, List<Map<String, dynamic>> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 6),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${item['title']} (${_percent(item['similarity'])})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonPreview(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        value,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _badge(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 11))),
        ],
      ),
    );
  }

  String _percent(dynamic value) {
    if (value == null) return 'N/A';
    final number =
        value is num ? value.toDouble() : double.tryParse(value.toString());
    if (number == null) return 'N/A';
    final percent = number > 1 ? number : number * 100;
    return '${percent.toStringAsFixed(1)}%';
  }

  String _methodLabel(String? method) {
    switch (method) {
      case 'logistic_regression':
        return 'Logistic Regression';
      case 'tfidf_rbl':
        return 'TF-IDF RBL';
      case 'rbl_keyword':
        return 'Keyword RBL';
      case 'fuzzy_match':
        return 'Fuzzy Match';
      default:
        return method ?? 'N/A';
    }
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _formatDate(String? value) {
    if (value == null) return 'N/A';
    try {
      final date = DateTime.parse(value);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }
}
