import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uni_track/services/mobile_data_service.dart';

class AiAssistantPage extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const AiAssistantPage({super.key, this.userData});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _data = MobileDataService();
  final _queryController = TextEditingController();
  final _complaintController = TextEditingController();

  bool _isLoading = false;
  bool _runningOperation = false;
  int _topK = 5;
  Map<String, dynamic>? _result;
  String? _error;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final responses = await Future.wait([
        _data.getAiStatus(),
        _data.getAiStats(),
      ]);
      if (mounted) {
        setState(() {
          _status = responses[0];
        });
      }
    } catch (_) {}
  }

  Future<void> _retrieve() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _data.getAiRetrieve(query: query, topK: _topK);
      if (mounted) {
        setState(() {
          _result = response;
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

  Future<void> _runOperation(
      String label, Future<Map<String, dynamic>> Function() action) async {
    setState(() => _runningOperation = true);
    try {
      final response = await action();
      if (mounted) {
        setState(() {
          _result = response;
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$label completed'), backgroundColor: Colors.green),
        );
        await _loadStatus();
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
      if (mounted) setState(() => _runningOperation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('AI Assistant'),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.green),
            onPressed: () {
              _loadStatus();
              if (_queryController.text.trim().isNotEmpty) _retrieve();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverview(),
            const SizedBox(height: 16),
            _buildQueryCard(),
            const SizedBox(height: 16),
            _buildOperationsCard(),
            const SizedBox(height: 16),
            _buildResultCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview() {
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
            'RAG, NLP, ITE and Escalation Engine',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ask the knowledge base to route, classify, explain and verify complaints using the same engine as the web app.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
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
          if (pipelines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Pipelines: ${pipelines.join(', ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _featureChip(String label, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: enabled ? Colors.white.withOpacity(0.2) : Colors.black12,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label ${enabled ? 'ON' : 'OFF'}',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildQueryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RAG Retrieval',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Describe the issue or ask a routing question',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Top results'),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _topK.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _topK.toString(),
                  onChanged: (value) => setState(() => _topK = value.round()),
                ),
              ),
              Text('$_topK', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _retrieve,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: const Text('Retrieve'),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () {
                  _queryController.clear();
                  setState(() => _result = null);
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.grey[700]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ITE Operations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _operationButton(
                  'Escalation Check',
                  Icons.trending_up,
                  Colors.purple,
                  () => _runOperation(
                      'Escalation check', _data.runAiEscalationCheck)),
              _operationButton('Batch Agent', Icons.auto_awesome, Colors.blue,
                  () => _runOperation('Batch agent', _data.runAiBatch)),
              _operationButton(
                  'Incremental Update',
                  Icons.update,
                  Colors.orange,
                  () => _runOperation(
                      'Incremental update', _data.applyIncrementalUpdate)),
              _operationButton('Retrain Models', Icons.psychology, Colors.green,
                  () => _runOperation('Model retrain', _data.retrainAiModels)),
            ],
          ),
          const SizedBox(height: 12),
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
            onPressed: _runningOperation
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
                    _runOperation('Document verification',
                        () => _data.verifyAllDocuments(id));
                  },
            icon: const Icon(Icons.folder_shared),
            label: const Text('Verify Documents'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          ),
        ],
      ),
    );
  }

  Widget _operationButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _runningOperation ? null : onTap,
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

  Widget _buildResultCard() {
    if (_isLoading || _runningOperation) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(color: Colors.green),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red[200]!)),
        child: Text(_error!, style: TextStyle(color: Colors.red[700])),
      );
    }

    if (_result == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 56, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text('AI results will appear here',
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    return _resultCard(_result!);
  }

  Widget _resultCard(Map<String, dynamic> result) {
    final retrieval = result['retrieval'] as Map<String, dynamic>?;
    final duplicates =
        List<Map<String, dynamic>>.from(result['duplicates'] ?? []);
    final suggestions =
        List<Map<String, dynamic>>.from(result['suggestions'] ?? []);
    final recommendations =
        List<Map<String, dynamic>>.from(result['recommendations'] ?? []);
    final decision = result['decision'] as Map<String, dynamic>?;
    final rag = result['rag'] as Map<String, dynamic>?;
    final resultResult = result['result'];
    final stats = result['stats'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Result',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (retrieval != null) ...[
            _detail('Office', retrieval['officeName']?.toString() ?? 'N/A'),
            _detail('Category', retrieval['categoryName']?.toString() ?? 'N/A'),
            _detail('Confidence', _percent(retrieval['confidence'])),
            _detail('Reasoning', retrieval['reasoning']?.toString() ?? 'N/A'),
          ],
          if (rag != null) ...[
            _detail('Routed Office', rag['officeName']?.toString() ?? 'N/A'),
            _detail('RAG Confidence', _percent(rag['confidence'])),
            _detail('RAG Reasoning', rag['reasoning']?.toString() ?? 'N/A'),
          ],
          if (decision != null) ...[
            _detail(
                'Escalate', decision['shouldEscalate'] == true ? 'Yes' : 'No'),
            _detail('Urgency', _percent(decision['urgencyScore'])),
            _detail('Reason', decision['reason']?.toString() ?? 'N/A'),
          ],
          _listSection(
              'Word Category Suggestions',
              _stringList(suggestions.map(
                  (s) => '${s['categoryName']} (${_percent(s['score'])})'))),
          _listSection(
              'Word Office Suggestions',
              _stringList(suggestions
                  .map((s) => '${s['officeName']} (${_percent(s['score'])})'))),
          _listSection(
              'Duplicates',
              _stringList(duplicates
                  .map((d) => '${d['title']} (${_percent(d['similarity'])})'))),
          _listSection('Recommendations',
              _stringList(recommendations.map((r) => r.toString()))),
          if (resultResult != null)
            _detail('Operation Result', resultResult.toString()),
          if (stats != null) _jsonPreview(jsonEncode(stats)),
          _jsonPreview(jsonEncode(result)),
        ],
      ),
    );
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

  Widget _listSection(String label, List<String> values) {
    if (values.isEmpty) return const SizedBox.shrink();
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
          ...values.map((value) => Padding(
              padding: const EdgeInsets.only(top: 4), child: Text('• $value'))),
        ],
      ),
    );
  }

  Widget _jsonPreview(String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
        child: Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!));
  }

  String _percent(dynamic value) {
    if (value == null) return 'N/A';
    final number =
        value is num ? value.toDouble() : double.tryParse(value.toString());
    if (number == null) return 'N/A';
    final percent = number > 1 ? number : number * 100;
    return '${percent.toStringAsFixed(1)}%';
  }

  List<String> _stringList(Iterable<dynamic> values) {
    return values
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
  }
}
