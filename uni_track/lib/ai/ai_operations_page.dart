import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uni_track/services/mobile_data_service.dart';

class AiOperationsPage extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const AiOperationsPage({super.key, this.userData});

  @override
  State<AiOperationsPage> createState() => _AiOperationsPageState();
}

class _AiOperationsPageState extends State<AiOperationsPage> {
  final _data = MobileDataService();
  final _complaintController = TextEditingController();

  bool _isLoading = false;
  bool _running = false;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _lastResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final responses = await Future.wait([
        _data.getAiStatus(),
        _data.getAiStats(),
      ]);
      if (mounted) {
        setState(() {
          _status = responses[0];
          _stats =
              responses[1]['stats'] as Map<String, dynamic>? ?? responses[1];
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

  Future<void> _run(
      String label, Future<Map<String, dynamic>> Function() action) async {
    setState(() => _running = true);
    try {
      final response = await action();
      if (mounted) {
        setState(() {
          _lastResult = response;
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$label completed'), backgroundColor: Colors.green),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$label failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('AI Operations'),
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatus(),
                  const SizedBox(height: 16),
                  _buildOperations(),
                  const SizedBox(height: 16),
                  _buildResult(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatus() {
    final features = _status?['features'] as Map<String, dynamic>? ?? {};
    final pipelines = _stringList(_status?['pipelines']);

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
          const Text(
            'AI Engine Status',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _status?['status']?.toString() ?? 'Unknown',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip(
                  'Documents', _status?['documentsIndexed']?.toString() ?? '0'),
              _statusChip('Attachments',
                  _status?['attachmentsIndexed']?.toString() ?? '0'),
              _statusChip('Models', _stats?['modelCount']?.toString() ?? '0'),
              _statusChip('Pending Feedback',
                  _stats?['pendingFeedback']?.toString() ?? '0'),
            ],
          ),
          if (pipelines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Pipelines: ${pipelines.join(', ')}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _featureChip('Routing', features['routingVerification'] == true),
              _featureChip('Batch', features['batchProcessing'] == true),
              _featureChip('Attachments', features['attachmentAware'] == true),
              _featureChip(
                  'Documents', features['documentVerification'] == true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999)),
      child: Text('$label: $value',
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _featureChip(String label, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: enabled ? Colors.white.withOpacity(0.2) : Colors.black12,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildOperations() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Operations',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _operationButton(
                  'Escalation Check',
                  Icons.trending_up,
                  Colors.purple,
                  () => _run('Escalation check', _data.runAiEscalationCheck)),
              _operationButton('Run Batch Agent', Icons.auto_awesome,
                  Colors.blue, () => _run('Batch agent', _data.runAiBatch)),
              _operationButton(
                  'Incremental Learning',
                  Icons.update,
                  Colors.orange,
                  () =>
                      _run('Incremental update', _data.applyIncrementalUpdate)),
              _operationButton('Retrain Models', Icons.psychology, Colors.green,
                  () => _run('Model retrain', _data.retrainAiModels)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _complaintController,
            decoration: InputDecoration(
              labelText: 'Complaint ID for document verification',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _running
                ? null
                : () {
                    final id = _complaintController.text.trim();
                    if (id.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Enter a complaint id'),
                            backgroundColor: Colors.orange),
                      );
                      return;
                    }
                    _run('Document verification',
                        () => _data.verifyAllDocuments(id));
                  },
            icon: const Icon(Icons.folder_shared),
            label: const Text('Verify Documents'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!)),
              child: Text(_error!, style: TextStyle(color: Colors.red[700])),
            ),
          ],
        ],
      ),
    );
  }

  Widget _operationButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _running ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    if (_lastResult == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Last Operation Result',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _jsonPreview(jsonEncode(_lastResult)),
        ],
      ),
    );
  }

  Widget _jsonPreview(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
      child: Text(value,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!));
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
