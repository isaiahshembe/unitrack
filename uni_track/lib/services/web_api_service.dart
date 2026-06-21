import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/config/app_config.dart';

class WebApiException implements Exception {
  final String message;
  final int? statusCode;

  WebApiException(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null ? message : '$message ($statusCode)';
}

class WebApiService {
  static final WebApiService _instance = WebApiService._internal();
  factory WebApiService() => _instance;
  WebApiService._internal();

  final http.Client _client = http.Client();
  String? _legacySessionToken;

  Uri _url(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('${AppConfig.webApiUrl}$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
        queryParameters: query.map((k, v) => MapEntry(k, v.toString())));
  }

  Future<Map<String, String>?> _authHeaders() async {
    if (_legacySessionToken != null) {
      return {
        'X-Unitrack-Mobile-Session': _legacySessionToken!,
        'Content-Type': 'application/json',
      };
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    return {
      'Authorization': 'Bearer ${session.accessToken}',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    final authHeaders = await _authHeaders();
    if (requireAuth && authHeaders == null) {
      throw WebApiException('Login session expired. Please sign in again.');
    }

    final requestHeaders = <String, String>{
      if (authHeaders != null) ...authHeaders,
      if (headers != null) ...headers,
    };

    Future<http.Response> send() async {
      final url = _url(path, query);
      final encodedBody = body == null ? null : jsonEncode(body);

      switch (method.toUpperCase()) {
        case 'GET':
          return _client.get(url, headers: requestHeaders);
        case 'POST':
          return _client.post(
            url,
            headers: requestHeaders,
            body: encodedBody,
          );
        case 'PATCH':
          return _client.patch(
            url,
            headers: requestHeaders,
            body: encodedBody,
          );
        case 'PUT':
          return _client.put(
            url,
            headers: requestHeaders,
            body: encodedBody,
          );
        case 'DELETE':
          return _client.delete(url, headers: requestHeaders);
        default:
          throw WebApiException('Unsupported HTTP method: $method');
      }
    }

    final response = await send().timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decode(response.body);
      final message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'Web API request failed';
      throw WebApiException(message, statusCode: response.statusCode);
    }

    return _decode(response.body) as Map<String, dynamic>;
  }

  dynamic _decode(String body) {
    if (body.trim().isEmpty) return {};
    return jsonDecode(body);
  }

  List<Map<String, dynamic>> _listResponse(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return const [];
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final data =
        await _request('GET', '/api/mobile/categories', requireAuth: false);
    return _listResponse(data);
  }

  Future<List<Map<String, dynamic>>> getOffices() async {
    final data =
        await _request('GET', '/api/mobile/offices', requireAuth: false);
    return _listResponse(data);
  }

  Future<Map<String, dynamic>> createComplaint({
    required String title,
    required String description,
    required int categoryId,
    int? officeId,
    String? location,
    double? gpsLatitude,
    double? gpsLongitude,
    bool isAnonymous = false,
    String? attachmentUrl,
    String? attachmentName,
    String? attachmentType,
    int? attachmentSize,
  }) async {
    return _request(
      'POST',
      '/api/mobile/complaints',
      body: {
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'officeId': officeId,
        'location': location,
        'gpsLatitude': gpsLatitude,
        'gpsLongitude': gpsLongitude,
        'isAnonymous': isAnonymous,
        'attachmentUrl': attachmentUrl,
        'attachmentName': attachmentName,
        'attachmentType': attachmentType,
        'attachmentSize': attachmentSize,
      },
    );
  }

  Future<Map<String, dynamic>> getComplaints({
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    return _request(
      'GET',
      '/api/mobile/complaints',
      query: {
        if (status != null) 'status': status,
        if (search != null) 'search': search,
        'page': page,
        'limit': limit,
      },
    );
  }

  Future<Map<String, dynamic>> getComplaint(String id) async {
    return _request('GET', '/api/mobile/complaints/$id');
  }

  Future<Map<String, dynamic>> signInMobileAuth(
    String email,
    String password,
  ) async {
    final response = await _client
        .post(
          _url('/api/mobile/auth'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decode(response.body);
      final message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'Admin AI session request failed';
      throw WebApiException(message, statusCode: response.statusCode);
    }

    final data = _decode(response.body) as Map<String, dynamic>;
    _legacySessionToken = data['token']?.toString();
    return data;
  }

  Future<Map<String, dynamic>> signInLegacyAdminAuth(
    String email,
    String password,
  ) async {
    final response = await _client
        .post(
          _url('/api/mobile/legacy-admin-auth'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decode(response.body);
      final message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'Legacy admin auth failed';
      throw WebApiException(message, statusCode: response.statusCode);
    }

    final data = _decode(response.body) as Map<String, dynamic>;
    _legacySessionToken = data['token']?.toString();
    return data;
  }

  Future<Map<String, dynamic>> getAiInspect(String complaintId) async {
    return _request('GET', '/api/mobile/ai-inspect/$complaintId');
  }

  Future<Map<String, dynamic>> postAiInspect({
    required String complaintId,
    required String action,
  }) async {
    return _request(
      'POST',
      '/api/mobile/ai-inspect/$complaintId',
      query: {'action': action},
      body: {},
    );
  }

  Future<Map<String, dynamic>> patchComplaintAction({
    required String complaintId,
    required String action,
  }) async {
    return _request(
      'PATCH',
      '/api/mobile/complaints/$complaintId',
      body: {'action': action},
    );
  }

  Future<Map<String, dynamic>> getAi({
    required String action,
    Map<String, dynamic>? query,
  }) async {
    return _request(
      'GET',
      '/api/mobile/ai',
      query: {'action': action, ...(query ?? {})},
    );
  }

  Future<Map<String, dynamic>> getAiStatus() async {
    return getAi(action: 'status');
  }

  Future<Map<String, dynamic>> getAiStats() async {
    return getAi(action: 'stats');
  }

  Future<Map<String, dynamic>> getAiSuggestion({
    required String title,
    required String description,
  }) async {
    return _request(
      'POST',
      '/api/mobile/ai/suggest',
      body: {
        'title': title,
        'description': description,
      },
    );
  }

  Future<Map<String, dynamic>> getAiRetrieve({
    required String query,
    int topK = 5,
  }) async {
    return postAi({
      'action': 'retrieve',
      'query': query,
      'topK': topK,
    });
  }

  Future<Map<String, dynamic>> runAiEscalationCheck() async {
    return getAi(action: 'escalation-check');
  }

  Future<Map<String, dynamic>> runAiBatch({
    double minConfidence = 0.35,
    int topK = 50,
  }) async {
    return postAi({
      'action': 'run-batch',
      'minConfidence': minConfidence,
      'topK': topK,
    });
  }

  Future<Map<String, dynamic>> retrainAiModels() async {
    return getAi(action: 'retrain');
  }

  Future<Map<String, dynamic>> applyIncrementalUpdate() async {
    return postAi({'action': 'apply-incremental-update'});
  }

  Future<Map<String, dynamic>> verifyAllDocuments(String complaintId) async {
    return getAi(
      action: 'verify-all-documents',
      query: {'complaintId': complaintId},
    );
  }

  Future<List<Map<String, dynamic>>> getEscalationChains(
    int categoryId,
  ) async {
    final data = await _request(
      'GET',
      '/api/mobile/escalation-chains',
      query: {'categoryId': categoryId},
      requireAuth: false,
    );
    return _listResponse(data);
  }

  Future<Map<String, dynamic>> postAi(Map<String, dynamic> body) async {
    return _request('POST', '/api/mobile/ai', body: body);
  }

  Future<Map<String, dynamic>> getAdminDashboard() async {
    return _request('GET', '/api/mobile/admin/dashboard');
  }

  Future<List<Map<String, dynamic>>> getAdminComplaints({
    String? status,
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _request(
      'GET',
      '/api/mobile/admin/complaints',
      query: {
        if (status != null) 'status': status,
        if (search != null) 'search': search,
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );
    return _listResponse(data['complaints'] ?? []);
  }

  Future<void> updateComplaintStatus({
    required String complaintId,
    required String status,
    String? rejectionReason,
  }) async {
    await _request(
      'PATCH',
      '/api/mobile/admin/complaints/$complaintId/status',
      body: {
        'status': status,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getComments(String complaintId) async {
    final data = await _request(
      'GET',
      '/api/mobile/admin/complaints/$complaintId/comments',
    );
    return _listResponse(data['comments'] ?? []);
  }

  Future<Map<String, dynamic>> addComment({
    required String complaintId,
    required String comment,
  }) async {
    return _request(
      'POST',
      '/api/mobile/admin/complaints/$complaintId/comments',
      body: {'comment': comment},
    );
  }

  Future<void> escalateComplaint(String complaintId) async {
    await _request(
      'PATCH',
      '/api/mobile/complaints/$complaintId',
      body: {'action': 'escalate'},
    );
  }

  Future<Map<String, dynamic>> getOfficesList() async {
    return _request('GET', '/api/mobile/admin/offices', requireAuth: false);
  }
}
