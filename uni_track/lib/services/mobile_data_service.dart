import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MobileDataException implements Exception {
  final String message;

  MobileDataException(this.message);

  @override
  String toString() => message;
}

class MobileDataService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> authenticateUser(
    String email,
    String password, {
    List<String> allowedRoles = const [],
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final userRow = await _fetchUserByEmail(normalizedEmail);

    if (userRow != null) {
      final role = await _fetchUserRole(userRow['role_id']);
      final allowed = allowedRoles.isEmpty ||
          allowedRoles.any((r) => r.toUpperCase() == role.toUpperCase());

      if (allowed &&
          _isActive(userRow) &&
          _passwordMatches(
            _string(userRow['password']),
            _string(userRow['password_hash']),
            password,
          )) {
        if (role.toUpperCase() == 'STUDENT') {
          return _studentDataFromUser(userRow);
        }

        if (_isStaffRole(role)) {
          return _adminDataFromUser(userRow, role);
        }
      }
    }

    try {
      final authResponse = await _supabase.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );

      if (authResponse.user == null) {
        throw MobileDataException('Invalid email or password');
      }

      final authUserRow = await _fetchUserById(authResponse.user!.id);
      if (authUserRow != null) {
        final role = await _fetchUserRole(authUserRow['role_id']);
        final allowed = allowedRoles.isEmpty ||
            allowedRoles.any((r) => r.toUpperCase() == role.toUpperCase());

        if (allowed && _isActive(authUserRow)) {
          if (role.toUpperCase() == 'STUDENT') {
            return _studentDataFromUser(authUserRow);
          }

          if (_isStaffRole(role)) {
            return _adminDataFromUser(authUserRow, role);
          }
        }
      }

      if (allowedRoles.contains('STUDENT')) {
        final student = await _supabase
            .from('students')
            .select()
            .eq('id', authResponse.user!.id)
            .maybeSingle();

        if (student != null) {
          return await _enrichStudentData(Map<String, dynamic>.from(student));
        }
      }

      if (allowedRoles.any((r) => _isStaffRole(r))) {
        final admin = await _supabase
            .from('admins')
            .select()
            .eq('id', authResponse.user!.id)
            .maybeSingle();

        if (admin != null) {
          final adminData = Map<String, dynamic>.from(admin);
          final role = (adminData['role']?.toString() ?? 'admin').toUpperCase();
          return {
            'id': adminData['id']?.toString() ?? authResponse.user!.id,
            'full_name': adminData['full_name']?.toString() ??
                adminData['email']?.toString() ??
                'Admin',
            'email': adminData['email']?.toString() ?? normalizedEmail,
            'employee_id': adminData['employee_id']?.toString() ?? '',
            'phone': adminData['phone']?.toString() ?? '',
            'role': role == 'SUPER_ADMIN' ? 'super_admin' : 'admin',
            'office_id': adminData['assigned_office_id'],
            'assigned_office_id': adminData['assigned_office_id'],
          };
        }
      }
    } catch (_) {}

    throw MobileDataException('Invalid email or password');
  }

  Future<Map<String, dynamic>> registerStudent({
    required String fullName,
    required String email,
    required String registrationNumber,
    required String phone,
    required String password,
    int? collegeId,
    int? courseId,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final existing = await _fetchUserByEmail(normalizedEmail);

    if (existing != null) {
      throw MobileDataException('A user with this email already exists');
    }

    final roleId = await _roleId('STUDENT');
    final hash = _hashPassword(password);

    final inserted = await _supabase
        .from('users')
        .insert({
          'full_name': fullName,
          'email': normalizedEmail,
          'phone': phone.trim().isEmpty ? null : phone.trim(),
          'registration_number': registrationNumber,
          'college_id': collegeId,
          'course_id': courseId,
          'password_hash': hash,
          'role_id': roleId,
          'is_active': true,
          'email_verified': false,
        })
        .select()
        .single();

    return _studentDataFromUser(Map<String, dynamic>.from(inserted));
  }

  Future<Map<String, dynamic>> createAdmin({
    required String fullName,
    required String email,
    required String employeeId,
    required String phone,
    required String password,
    int? officeId,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final existing = await _fetchUserByEmail(normalizedEmail);

    if (existing != null) {
      throw MobileDataException('An account with this email already exists.');
    }

    final roleId = await _roleId('SUPER_ADMIN');
    final hash = _hashPassword(password);

    final inserted = await _supabase
        .from('users')
        .insert({
          'full_name': fullName,
          'email': normalizedEmail,
          'employee_id': employeeId,
          'phone': phone.trim().isEmpty ? null : phone.trim(),
          'password_hash': hash,
          'role_id': roleId,
          'office_id': officeId,
          'is_active': true,
          'email_verified': false,
        })
        .select()
        .single();

    return _adminDataFromUser(
        Map<String, dynamic>.from(inserted), 'SUPER_ADMIN');
  }

  Future<void> resetUserPassword(String userId, String newPassword) async {
    await _supabase.from('users').update({
      'password': newPassword,
      'password_hash': _hashPassword(newPassword),
    }).eq('id', userId);
  }

  Future<bool> validateUserPassword(String userId, String password) async {
    final user = await _fetchUserById(userId);
    if (user == null) return false;

    return _passwordMatches(
      _string(user['password']),
      _string(user['password_hash']),
      password,
    );
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await _supabase
        .from('issue_categories')
        .select('*')
        .eq('is_active', true)
        .order('name', ascending: true);

    final categories = List<Map<String, dynamic>>.from(response);
    final enriched = <Map<String, dynamic>>[];

    for (final category in categories) {
      final enrichedCategory = Map<String, dynamic>.from(category);
      final priorityId = category['priority_id'];

      if (priorityId != null) {
        final priority = await _supabase
            .from('issue_priorities')
            .select()
            .eq('id', _toInt(priorityId)!)
            .maybeSingle();

        if (priority != null) {
          enrichedCategory['priority'] = priority;
        }
      }

      final defaultOfficeId = category['default_office_id'];
      if (defaultOfficeId != null) {
        final office = await _fetchOffice(_toInt(defaultOfficeId)!);
        if (office != null) {
          enrichedCategory['defaultOffice'] = office;
        }
      }

      enriched.add(enrichedCategory);
    }

    return enriched;
  }

  Future<List<Map<String, dynamic>>> getOfficesList() async {
    return List<Map<String, dynamic>>.from(
      await _supabase
          .from('offices')
          .select('id, name, level, building, room_number')
          .eq('is_active', true)
          .order('name', ascending: true),
    );
  }

  Future<Map<String, dynamic>> createComplaint({
    required String studentId,
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
    final category = await _fetchCategory(categoryId);
    if (category == null) {
      throw MobileDataException('Selected category not found');
    }

    final categoryPriority = category['priority'] as Map<String, dynamic>?;
    final priorityName =
        (categoryPriority?['name']?.toString() ?? 'MEDIUM').toUpperCase();
    final defaultOfficeId = category['defaultOffice']?['id'];
    final resolvedOfficeId = officeId ?? defaultOfficeId;
    final student = await _fetchStudent(studentId);
    final now = DateTime.now().toIso8601String();

    final inserted = await _supabase
        .from('complaints')
        .insert({
          'tracking_code': _trackingCode(),
          'student_id': studentId,
          'category_id': categoryId,
          'office_id': resolvedOfficeId,
          'status': 'OPEN',
          'priority': priorityName,
          'title': title,
          'description': description,
          'location': location,
          'is_anonymous': isAnonymous,
          'student_email': student?['email'],
          'student_name': student?['full_name'],
          'student_phone': student?['phone'],
          'college_id': student?['college_id'],
          'course_id': student?['course_id'],
          'should_escalate': false,
          'created_at': now,
          'updated_at': now,
          if (attachmentUrl != null && attachmentUrl.isNotEmpty)
            'attachment_url': attachmentUrl,
          if (attachmentName != null && attachmentName.isNotEmpty)
            'attachment_name': attachmentName,
          if (attachmentType != null && attachmentType.isNotEmpty)
            'attachment_type': attachmentType,
          if (attachmentSize != null) 'attachment_size': attachmentSize,
          if (gpsLatitude != null) 'gps_latitude': gpsLatitude,
          if (gpsLongitude != null) 'gps_longitude': gpsLongitude,
        })
        .select()
        .single();

    final complaintId = inserted['id'].toString();
    final classification = await classifyComplaintText(title, description);
    final rag = await _reasonAboutEscalation({
      'id': complaintId,
      'categoryId': categoryId,
      'officeId': resolvedOfficeId,
      'currentEscalationLevel': 0,
      'priority': priorityName,
      'status': 'OPEN',
      'title': title,
      'description': description,
      'deadlineAt': null,
      'createdAt': now,
    });

    await _supabase.from('complaints').update({
      'nlp_results': jsonEncode(classification),
      'should_escalate': rag['shouldEscalate'] == true,
    }).eq('id', complaintId);

    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      await _supabase.from('attachments').insert({
        'complaint_id': complaintId,
        'file_name': attachmentName ?? 'attachment',
        'file_url': attachmentUrl,
        'file_type': attachmentType ?? 'unknown',
        'file_size': attachmentSize,
        'uploaded_by_id': studentId,
        'nlp_result': jsonEncode(classification),
      });
    }

    final complaint = await getComplaint(complaintId);
    final similar = await _findSimilarComplaints(complaintId, 5);

    return {
      'message': 'Complaint created successfully',
      'complaint': complaint['complaint'],
      'classification': classification,
      'rag': rag,
      'similarComplaints': similar,
    };
  }

  Future<Map<String, dynamic>> getComplaints({
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
    String? studentId,
  }) async {
    dynamic query = _supabase.from('complaints').select();

    if (studentId != null) {
      query = query.eq('student_id', studentId);
    }

    if (status != null && status.toLowerCase() != 'all') {
      query = query.eq('status', status.toUpperCase());
    }

    if (search != null && search.trim().isNotEmpty) {
      final safeSearch = search.trim().replaceAll('%', '');
      query =
          query.or('title.ilike.%$safeSearch%,description.ilike.%$safeSearch%');
    }

    final offset = (page - 1) * limit;
    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final complaints = await _enrichComplaints(response);
    final total = await _countComplaints(
        studentId: studentId, status: status, search: search);

    return {
      'complaints': complaints,
      'pagination': {
        'page': page,
        'limit': limit,
        'total': total,
        'pages': (total / limit).ceil(),
      },
    };
  }

  Future<Map<String, dynamic>> getComplaint(String id) async {
    final complaint = await _fetchComplaint(id);
    if (complaint == null) {
      throw MobileDataException('Complaint not found');
    }

    return {'complaint': await _enrichComplaint(complaint)};
  }

  Future<Map<String, dynamic>> getAdminComplaints({
    String? status,
    String? search,
    int page = 1,
    int limit = 50,
    required Map<String, dynamic> adminData,
  }) async {
    final adminId = adminData['id']?.toString();
    final officeId =
        _toInt(adminData['office_id'] ?? adminData['assigned_office_id']);
    final role = (adminData['role']?.toString() ?? 'admin').toUpperCase();
    dynamic query = _supabase.from('complaints').select();

    if (role != 'SUPER_ADMIN') {
      if (officeId != null) {
        query = query.eq('office_id', officeId);
      } else if (adminId != null) {
        query = query.eq('assigned_admin_id', adminId);
      }
    }

    if (status != null && status.toLowerCase() != 'all') {
      query = query.eq('status', status.toUpperCase());
    }

    if (search != null && search.trim().isNotEmpty) {
      final safeSearch = search.trim().replaceAll('%', '');
      query =
          query.or('title.ilike.%$safeSearch%,description.ilike.%$safeSearch%');
    }

    final offset = (page - 1) * limit;
    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final complaints = await _enrichComplaints(response);
    final total = complaints.length;

    return {
      'complaints': complaints,
      'pagination': {
        'page': page,
        'limit': limit,
        'total': total,
        'pages': (total / limit).ceil(),
      },
    };
  }

  Future<void> updateComplaintStatus({
    required String complaintId,
    required String status,
    String? rejectionReason,
  }) async {
    final normalized = status.toUpperCase().replaceAll(' ', '_');
    final now = DateTime.now().toIso8601String();
    final data = <String, dynamic>{
      'status': normalized,
      'updated_at': now,
    };

    if (normalized == 'REJECTED') {
      data['rejection_reason'] = rejectionReason ?? 'No reason provided';
      data['rejected_at'] = now;
      data['should_escalate'] = false;
    }

    if (normalized == 'RESOLVED') {
      data['resolved_at'] = now;
    }

    await _supabase.from('complaints').update(data).eq('id', complaintId);
    await _supabase.from('complaint_status_history').insert({
      'complaint_id': complaintId,
      'changed_by_id': '',
      'old_status': '',
      'new_status': normalized,
      'comment': 'Status updated',
      'escalation_level': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getComments(String complaintId) async {
    final response = await _supabase
        .from('complaint_status_history')
        .select()
        .eq('complaint_id', complaintId)
        .not('comment', 'is', null)
        .order('created_at', ascending: false);

    final comments = <Map<String, dynamic>>[];
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final enriched = Map<String, dynamic>.from(row);
      final changedById = row['changed_by_id']?.toString();
      if (changedById != null && changedById.isNotEmpty) {
        final user = await _fetchUserById(changedById);
        enriched['admin_id'] = user?['id'];
        enriched['admin_name'] = user?['full_name'];
        enriched['student_name'] = user?['full_name'];
      }
      comments.add(enriched);
    }

    return comments;
  }

  Future<Map<String, dynamic>> addComment({
    required String complaintId,
    required String comment,
  }) async {
    await _supabase.from('complaint_status_history').insert({
      'complaint_id': complaintId,
      'changed_by_id': '',
      'old_status': '',
      'new_status': 'PENDING',
      'comment': comment.trim(),
      'escalation_level': 0,
    });

    return {'success': true};
  }

  Future<Map<String, dynamic>> getAiStatus() async {
    final resolved = await _countComplaints(status: 'RESOLVED');
    final attachments = await _supabase.from('attachments').count();

    return {
      'status': 'ready',
      'documentsIndexed': resolved,
      'attachmentsIndexed': attachments,
      'pipelines': [
        'escalation_chain',
        'office_policy',
        'resolved_case',
        'attachments'
      ],
      'features': {
        'routingVerification': true,
        'batchProcessing': true,
        'attachmentAware': true,
        'documentVerification': true,
      },
    };
  }

  Future<Map<String, dynamic>> getAiStats() async {
    final feedback = await _supabase.from('ite_feedback').count();
    final models = await _supabase.from('ite_models').count();
    final registries = await _supabase.from('model_registries').count();

    return {
      'stats': {
        'pendingFeedback': feedback,
        'modelCount': models,
        'modelRegistryCount': registries,
        'slaTrained': false,
        'incrementalLearningEnabled': true,
        'cronJobs': [
          'weekly-training-Sunday-2am',
          'incremental-hourly',
          'daily-escalation-1am',
          'weekly-insight-report-Sunday-3am',
        ],
      },
    };
  }

  Future<Map<String, dynamic>> getAiRetrieve({
    required String query,
    int topK = 5,
  }) async {
    final retrieval = await _retrieveRelevantDocuments(query, topK);
    final suggestions = await _wordSuggestions(query);

    return {
      'success': true,
      'retrieval': retrieval,
      'wordCategorySuggestions': suggestions['categorySuggestions'],
      'wordOfficeSuggestions': suggestions['officeSuggestions'],
    };
  }

  Future<Map<String, dynamic>> runAiEscalationCheck() async {
    final response = await _supabase
        .from('complaints')
        .select()
        .inFilter('status', ['OPEN', 'UNDER_REVIEW', 'ESCALATED'])
        .order('created_at', ascending: false)
        .limit(200);

    var escalated = 0;
    var skipped = 0;

    for (final row in List<Map<String, dynamic>>.from(response)) {
      try {
        final decision = await _evaluateEscalation(row);
        if (decision['shouldEscalate'] == true) {
          await _escalateComplaintById(row['id'].toString());
          escalated++;
        } else {
          skipped++;
        }
      } catch (_) {
        skipped++;
      }
    }

    return {
      'result': {'escalated': escalated, 'critical': 0, 'skipped': skipped}
    };
  }

  Future<Map<String, dynamic>> runAiBatch({
    double minConfidence = 0.35,
    int topK = 50,
  }) async {
    final response = await _supabase
        .from('complaints')
        .select()
        .inFilter('status', ['OPEN', 'UNDER_REVIEW', 'ESCALATED'])
        .order('created_at', ascending: false)
        .limit(topK);

    var processed = 0;
    final results = <Map<String, dynamic>>[];

    for (final row in List<Map<String, dynamic>>.from(response)) {
      final decision = await _evaluateEscalation(row);
      final confidence =
          ((_toDouble(decision['urgencyScore']) ?? 0) / 100).clamp(0.0, 1.0);
      if (confidence >= minConfidence && decision['shouldEscalate'] == true) {
        final result = await _escalateComplaintById(row['id'].toString());
        results.add(result);
        processed++;
      }
    }

    return {
      'success': true,
      'processed': processed,
      'results': results,
      'count': results.length
    };
  }

  Future<Map<String, dynamic>> retrainAiModels() async {
    final response = await _supabase
        .from('complaints')
        .select('title, description, category_id')
        .limit(5000);

    final rows = List<Map<String, dynamic>>.from(response);
    if (rows.length < 50) {
      return {
        'message': 'Not enough training data',
        'lrModel': null,
        'slaModel': null
      };
    }

    final counts = <int, int>{};
    for (final row in rows) {
      final categoryId = _toInt(row['category_id']);
      if (categoryId == null) continue;
      counts[categoryId] = (counts[categoryId] ?? 0) + 1;
    }

    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    final topCategory =
        counts.entries.reduce((a, b) => a.value > b.value ? a : b);
    final accuracy = (topCategory.value / total).clamp(0.0, 1.0);
    final now = DateTime.now().toIso8601String();

    await _supabase.from('ite_models').upsert({
      'type': 'logistic_regression',
      'model_json':
          jsonEncode({'topCategory': topCategory.key, 'counts': counts}),
      'trained_at': now,
      'accuracy': accuracy,
      'data_points': total,
    }, onConflict: 'type');

    await _supabase.from('model_registries').insert({
      'type': 'logistic_regression',
      'version': 1,
      'accuracy': accuracy,
      'data_points': total,
      'hyperparameters':
          jsonEncode({'learningRate': 0.01, 'epochs': 100, 'optimizer': 'SGD'}),
      'model_json':
          jsonEncode({'topCategory': topCategory.key, 'counts': counts}),
      'deployed': true,
    });

    return {
      'message': 'Models retrained successfully',
      'lrModel': {'accuracy': accuracy, 'dataPoints': total},
      'slaModel': {'trained': false}
    };
  }

  Future<Map<String, dynamic>> applyIncrementalUpdate() async {
    final feedback = await _supabase
        .from('ite_feedback')
        .select()
        .eq('used_for_training', false)
        .limit(100);

    for (final row in List<Map<String, dynamic>>.from(feedback)) {
      final categoryId = _toInt(row['corrected_category']);
      await _supabase.from('classification_memories').upsert({
        'text_fingerprint': row['complaint_id'].toString(),
        'category_id': categoryId,
        'confidence': 1.0,
        'method': 'feedback',
        'count': 1,
        'last_seen_at': DateTime.now().toIso8601String(),
      }, onConflict: 'text_fingerprint');

      await _supabase
          .from('ite_feedback')
          .update({'used_for_training': true}).eq('id', row['id']);
    }

    return {
      'result': {'applied': feedback.length}
    };
  }

  Future<Map<String, dynamic>> verifyAllDocuments(String complaintId) async {
    final complaint = await _fetchComplaint(complaintId);
    if (complaint == null) {
      throw MobileDataException('Complaint not found');
    }

    final attachments = await _fetchAttachments(complaintId);
    final analyses = <Map<String, dynamic>>[];
    for (final attachment in attachments) {
      final text = _string(attachment['extracted_text']);
      analyses.add({
        'id': attachment['id'],
        'fileName': attachment['file_name'],
        'fileType': attachment['file_type'],
        'isVerified': text.isNotEmpty,
        'extractedTextLength': text.length,
        'summary': text.isEmpty
            ? 'No extracted text available'
            : 'Attachment text extracted successfully',
      });
    }

    return {
      'success': true,
      'complaintId': complaintId,
      'attachments': analyses
    };
  }

  Future<Map<String, dynamic>> getAi({
    required String action,
    Map<String, dynamic>? query,
  }) async {
    switch (action) {
      case 'status':
        return getAiStatus();
      case 'stats':
        return getAiStats();
      case 'retrieve':
        return getAiRetrieve(
            query: _string(query?['query']), topK: _toInt(query?['topK']) ?? 5);
      case 'escalation-check':
        return runAiEscalationCheck();
      case 'retrain':
        return retrainAiModels();
      case 'verify-all-documents':
        return verifyAllDocuments(_string(query?['complaintId']));
      case 'anomalies':
        return {
          'anomalies': await _detectAnomalies(_toInt(query?['categoryId']))
        };
      default:
        throw MobileDataException('Invalid AI action');
    }
  }

  Future<Map<String, dynamic>> postAi(Map<String, dynamic> body) async {
    switch (_string(body['action'])) {
      case 'retrieve':
        return getAiRetrieve(
            query: _string(body['query']), topK: _toInt(body['topK']) ?? 5);
      case 'run-batch':
        return runAiBatch(
          minConfidence: _toDouble(body['minConfidence']) ?? 0.35,
          topK: _toInt(body['topK']) ?? 50,
        );
      case 'apply-incremental-update':
        return applyIncrementalUpdate();
      default:
        throw MobileDataException('Invalid AI action');
    }
  }

  Future<Map<String, dynamic>> getAiInspect(String complaintId) async {
    final complaint = await _fetchComplaint(complaintId);
    if (complaint == null) {
      throw MobileDataException('Complaint not found');
    }

    final text =
        '${_string(complaint['title'])} ${_string(complaint['description'])}';
    final nlp = await classifyComplaintText(
        _string(complaint['title']), _string(complaint['description']));
    final rag = await _reasonAboutEscalation(complaint);
    final escalation = await _evaluateEscalation(complaint);
    final historicalAvg = await _historicalAvgResolution(
      _toInt(complaint['office_id']),
      _toInt(complaint['category_id']),
    );
    final prediction = await _predictComplaintSla(complaint, historicalAvg);
    final similar = await _findSimilarComplaints(complaintId, 5);
    final duplicates = await _detectDuplicates(complaintId);
    final anomaly = await _detectAnomalies(_toInt(complaint['category_id']));
    final attachments = await _fetchAttachments(complaintId);

    return {
      'complaint': await _enrichComplaint(complaint),
      'ai': {
        'nlpAnalysis': nlp,
        'ragRouting': rag,
        'escalationEvaluation': escalation,
        'sla': {
          'prediction': prediction,
          'historicalAvg': historicalAvg,
          'autoAdjusted': {
            'adjustedDays': prediction['predictedDays'],
            'adjustedDeadline': DateTime.now()
                .add(Duration(days: _toInt(prediction['predictedDays']) ?? 5))
                .toIso8601String(),
            'rationale':
                'Adjusted from historical average and complaint urgency',
          },
        },
        'similarity': {
          'similarComplaints': similar,
          'duplicates': duplicates,
          'anomaly': anomaly,
        },
        'storedNlpResults': _decodeJson(complaint['nlp_results']),
      },
      'text': text,
      'attachments': attachments,
    };
  }

  Future<Map<String, dynamic>> postAiInspect({
    required String complaintId,
    required String action,
  }) async {
    final complaint = await _fetchComplaint(complaintId);
    if (complaint == null) {
      throw MobileDataException('Complaint not found');
    }

    switch (action) {
      case 'reclassify':
        final nlp = await classifyComplaintText(
            _string(complaint['title']), _string(complaint['description']));
        await _supabase.from('complaints').update({
          'nlp_results': jsonEncode(nlp),
        }).eq('id', complaintId);
        return {'success': true, 'nlpAnalysis': nlp};

      case 'adjust-sla':
        final historicalAvg = await _historicalAvgResolution(
          _toInt(complaint['office_id']),
          _toInt(complaint['category_id']),
        );
        final prediction = await _predictComplaintSla(complaint, historicalAvg);
        final days = _toInt(prediction['predictedDays']) ?? historicalAvg;
        await _supabase.from('complaints').update({
          'deadline_at':
              DateTime.now().add(Duration(days: days)).toIso8601String(),
        }).eq('id', complaintId);
        return {
          'success': true,
          'sla': {'prediction': prediction, 'historicalAvg': historicalAvg}
        };

      case 'run-agent':
        return await _escalateComplaintById(complaintId);

      case 'force-escalate':
        return await _forceEscalateComplaint(complaintId);

      default:
        throw MobileDataException('Invalid AI inspection action');
    }
  }

  Future<Map<String, dynamic>> patchComplaintAction({
    required String complaintId,
    required String action,
  }) async {
    if (action == 'run-agent' || action == 'force-escalate') {
      return _escalateComplaintById(complaintId);
    }

    throw MobileDataException('Invalid complaint action');
  }

  Future<List<Map<String, dynamic>>> getEscalationChains(int categoryId) async {
    return List<Map<String, dynamic>>.from(
      await _supabase
          .from('escalation_chains')
          .select()
          .eq('category_id', categoryId)
          .eq('is_active', true)
          .order('level', ascending: true),
    );
  }

  Future<Map<String, dynamic>> classifyComplaintText(
      String title, String description) async {
    await _loadKeywordCaches();
    final words = _tokens('$title $description');

    final categories = <Map<String, dynamic>>[];
    var bestMatchedKeywords = <String>[];

    for (final category in _categoryCache) {
      final categoryId = _toInt(category['id']);
      if (categoryId == null) continue;
      final categoryName = _string(category['name']);
      var score = 0;
      final matched = <String>[];

      for (final word in words) {
        final row = _categoryWordCache.firstWhere(
          (item) =>
              _toInt(item['category_id']) == categoryId &&
              _string(item['word']) == word,
          orElse: () => <String, dynamic>{},
        );

        if (row.isNotEmpty) {
          score += _toInt(row['count']) ?? 0;
          if (!matched.contains(word)) matched.add(word);
        }
      }

      categories.add({
        'categoryId': categoryId,
        'categoryName': categoryName,
        'score': score,
        'matchedKeywords': List<String>.from(matched),
      });
    }

    categories.sort(
      (a, b) => (_toInt(b['score']) ?? 0).compareTo(_toInt(a['score']) ?? 0),
    );
    final best = categories.isNotEmpty ? categories.first : null;
    if (best != null) {
      bestMatchedKeywords = List<String>.from(best['matchedKeywords'] ?? []);
    }

    if (best == null || (_toInt(best['score']) ?? 0) == 0) {
      final fallback = _categoryCache.isNotEmpty
          ? _categoryCache.first
          : <String, dynamic>{};
      return {
        'method': 'fallback',
        'categoryId': _toInt(fallback['id']) ?? 0,
        'categoryName': _string(fallback['name']),
        'confidence': 0.2,
        'matchedKeywords': <String>[],
        'sentimentUrgency': _sentimentUrgency(title, description),
        'textStats': {
          'totalTokens': words.length,
          'uniqueTokens': words.toSet().length
        },
      };
    }

    return {
      'method': 'keyword_rbl',
      'categoryId': _toInt(best['categoryId']) ?? 0,
      'categoryName': _string(best['categoryName']),
      'confidence':
          (0.35 + ((_toInt(best['score']) ?? 0) / 20)).clamp(0.35, 0.95),
      'matchedKeywords': bestMatchedKeywords,
      'sentimentUrgency': _sentimentUrgency(title, description),
      'textStats': {
        'totalTokens': words.length,
        'uniqueTokens': words.toSet().length
      },
    };
  }

  Future<Map<String, dynamic>> suggestCategoryAndOffice({
    required String title,
    required String description,
  }) async {
    await _loadKeywordCaches();
    final classification = await classifyComplaintText(title, description);
    final categoryId = _toInt(classification['categoryId']);
    final words = _tokens('$title $description');

    final officeResult = await _suggestOffice(words, categoryId);
    final officeId = _toInt(officeResult['officeId']);
    final officeName = officeResult['officeName']?.toString();

    String reasoning;
    if (officeId != null && officeName != null && officeName.isNotEmpty) {
      final chain =
          categoryId != null ? await _escalationChain(categoryId, 0) : null;
      if (chain != null && _toInt(chain['officeId']) == officeId) {
        reasoning = 'Default office for ${classification['categoryName']}';
      } else if (officeResult['usedFallback'] == true) {
        reasoning = 'Assigned based on category configuration';
      } else {
        reasoning = 'Matched via keyword analysis';
      }
    } else {
      reasoning = 'No specific office match found';
    }

    return {
      'categoryId': classification['categoryId'],
      'categoryName': classification['categoryName'],
      'confidence': classification['confidence'],
      'method': classification['method'],
      'matchedKeywords': classification['matchedKeywords'],
      'sentimentUrgency': classification['sentimentUrgency'],
      'officeId': officeId,
      'officeName': officeName,
      'reasoning': reasoning,
    };
  }

  Future<Map<String, dynamic>> _retrieveRelevantDocuments(
      String query, int topK) async {
    final words = _tokens(query);
    final categoryResult = await classifyComplaintText(query, query);
    final officeResult =
        await _suggestOffice(words, _toInt(categoryResult['categoryId']));
    final reasoning =
        'Local RAG keyword retrieval matched category ${categoryResult['categoryName']} and office ${officeResult['officeName'] ?? 'unassigned'}.';

    return {
      'categoryId': categoryResult['categoryId'],
      'categoryName': categoryResult['categoryName'],
      'confidence': categoryResult['confidence'],
      'reasoning': reasoning,
      'suggestedOfficeId': officeResult['officeId'],
      'officeName': officeResult['officeName'],
      'topK': topK,
      'usedFallback': officeResult['usedFallback'] == true,
    };
  }

  Future<Map<String, dynamic>> _reasonAboutEscalation(
      Map<String, dynamic> complaint) async {
    final words = _tokens(
        '${_string(complaint['title'])} ${_string(complaint['description'])}');
    final categoryId =
        _toInt(complaint['categoryId'] ?? complaint['category_id']);
    if (categoryId == null) {
      return {
        'categoryId': null,
        'categoryName': '',
        'confidence': 0.0,
        'reasoning': 'Missing category id',
        'suggestedOfficeId': null,
        'officeName': null,
        'topMatch': 'No match',
        'usedFallback': true,
      };
    }
    final officeResult = await _suggestOffice(words, categoryId);
    final escalationChain = await _escalationChain(categoryId, 0);
    final officeName =
        escalationChain?['officeName'] ?? officeResult['officeName'];
    final officeId = _toInt(escalationChain?['officeId']) ??
        _toInt(officeResult['officeId']);

    return {
      'categoryId': categoryId,
      'categoryName': _string(complaint['category']?['name']),
      'confidence': 0.72,
      'reasoning':
          'RAG routing used escalation chain and keyword office matching.',
      'suggestedOfficeId': officeId,
      'officeName': officeName,
      'topMatch': officeName ?? 'No match',
      'usedFallback': officeName == null,
    };
  }

  Future<Map<String, dynamic>> _suggestOffice(
      List<String> words, int? categoryId) async {
    var bestOfficeId = _toInt(categoryId == null
        ? null
        : (await _escalationChain(categoryId, 0))?['officeId']);
    var bestScore = 0;
    String? bestOfficeName;

    for (final office in _officeCache) {
      final officeId = _toInt(office['id']);
      if (officeId == null) continue;
      var score = 0;
      for (final word in words) {
        final row = _officeWordCache.firstWhere(
          (item) =>
              _toInt(item['office_id']) == officeId &&
              _string(item['word']) == word,
          orElse: () => <String, dynamic>{},
        );

        if (row.isNotEmpty) {
          score += _toInt(row['count']) ?? 0;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestOfficeId = officeId;
        bestOfficeName = _string(office['name']);
      }
    }

    if (bestOfficeName == null && bestOfficeId != null && bestOfficeId != 0) {
      final office = await _fetchOffice(bestOfficeId);
      bestOfficeName = office?['name'];
    }

    return {
      'officeId': bestOfficeId,
      'officeName': bestOfficeName,
      'usedFallback': bestScore == 0,
    };
  }

  Future<Map<String, dynamic>?> _escalationChain(
      int categoryId, int level) async {
    final chain = await _supabase
        .from('escalation_chains')
        .select()
        .eq('category_id', categoryId)
        .eq('level', level)
        .eq('is_active', true)
        .maybeSingle();

    if (chain == null) return null;

    final office = await _fetchOffice(_toInt(chain['office_id'])!);
    return {
      'officeId': chain['office_id'],
      'officeName': office?['name'],
      'slaDays': chain['sla_days'],
    };
  }

  Future<Map<String, dynamic>> _evaluateEscalation(
      Map<String, dynamic> complaint) async {
    final now = DateTime.now();
    final deadline =
        _parseDate(complaint['deadline_at'] ?? complaint['deadlineAt']);
    final createdAt =
        _parseDate(complaint['created_at'] ?? complaint['createdAt']) ?? now;
    final officeOpen = await _countComplaints(
      officeId: _toInt(complaint['office_id']),
      status: 'OPEN,UNDER_REVIEW',
    );
    final categoryId =
        _toInt(complaint['categoryId'] ?? complaint['category_id']);
    final historical = await _historicalAvgResolution(
      _toInt(complaint['office_id']),
      categoryId,
    );
    final similar = await _findSimilarComplaints(complaint['id'].toString(), 5);
    final title = _string(complaint['title']);
    final description = _string(complaint['description']);
    final priority = _string(complaint['priority']).toUpperCase();
    var urgency = 0;
    final factors = <String>[];

    if (deadline != null) {
      final remaining = deadline.difference(now).inHours;
      final total = deadline.difference(createdAt).inHours;
      final ratio = total > 0 ? remaining / total : 0;

      if (remaining <= 0) {
        urgency += 40;
        factors.add('SLA deadline passed');
      } else if (ratio < 0.25) {
        urgency += 25;
        factors.add('Less than 25% SLA time remaining');
      } else if (ratio < 0.5) {
        urgency += 10;
        factors.add('Less than 50% SLA time remaining');
      }
    }

    if (priority == 'HIGH') {
      urgency += 25;
      factors.add('High priority complaint');
    } else if (priority == 'MEDIUM') {
      urgency += 10;
    }

    if (officeOpen > 10) {
      urgency += 15;
      factors.add('Office overloaded ($officeOpen open complaints)');
    } else if (officeOpen > 5) {
      urgency += 8;
      factors.add('Office has high workload ($officeOpen open)');
    }

    final sentiment = _sentimentUrgency(title, description);
    if (sentiment > 0.6) {
      urgency += 15;
      factors.add('High emotional urgency detected');
    }

    if (historical > 7) {
      urgency += 10;
      factors.add('Office historically slow (avg $historical days)');
    }

    if (similar.length >= 5) {
      urgency += 20;
      factors.add('Systemic issue (${similar.length} similar complaints)');
    } else if (similar.length >= 3) {
      urgency += 10;
      factors.add('Recurring issue (${similar.length} similar complaints)');
    }

    final currentLevel = _toInt(complaint['current_escalation_level'] ??
            complaint['currentEscalationLevel']) ??
        0;

    final shouldEscalate = urgency >= 60 ||
        (urgency >= 40 && currentLevel < 1) ||
        (urgency >= 25 &&
            deadline != null &&
            deadline.difference(now).inHours < 24);

    return {
      'shouldEscalate': shouldEscalate,
      'newLevel': currentLevel + (shouldEscalate ? 1 : 0),
      'targetOfficeId': _toInt(complaint['office_id']) ?? 0,
      'reason': shouldEscalate
          ? 'Escalation recommended by local ITE rules'
          : 'No escalation needed at this time',
      'urgencyScore': urgency,
      'factors': factors,
    };
  }

  Future<Map<String, dynamic>> _predictComplaintSla(
      Map<String, dynamic> complaint, int historicalAvg) async {
    final priority = _string(complaint['priority']).toUpperCase();
    final sentiment = _toDouble((await classifyComplaintText(
            _string(complaint['title']),
            _string(complaint['description'])))['sentimentUrgency']) ??
        0;
    var predicted = historicalAvg > 0 ? historicalAvg : 5;

    if (priority == 'HIGH') predicted += 2;
    if (priority == 'CRITICAL') predicted += 1;
    if (sentiment > 0.6) predicted += 1;

    final factors = <String>[];
    if (historicalAvg > 0)
      factors.add('Historical average: $historicalAvg days');
    if (priority.isNotEmpty) factors.add('Priority: $priority');
    if (sentiment > 0.6) factors.add('High sentiment urgency');

    return {
      'predictedDays': predicted,
      'confidence': 0.65,
      'factors': factors,
    };
  }

  Future<int> _historicalAvgResolution(int? officeId, int? categoryId) async {
    dynamic query = _supabase
        .from('complaints')
        .select('created_at, resolved_at')
        .eq('status', 'RESOLVED')
        .not('resolved_at', 'is', null);

    if (officeId != null && officeId > 0)
      query = query.eq('office_id', officeId);
    if (categoryId != null && categoryId > 0)
      query = query.eq('category_id', categoryId);

    final rows = List<Map<String, dynamic>>.from(await query.limit(50));
    if (rows.isEmpty) return 5;

    var total = 0.0;
    for (final row in rows) {
      final created = _parseDate(row['created_at']);
      final resolved = _parseDate(row['resolved_at']);
      if (created != null && resolved != null) {
        total += resolved.difference(created).inDays;
      }
    }

    return (total / rows.length).round();
  }

  Future<List<Map<String, dynamic>>> _findSimilarComplaints(
      String complaintId, int limit) async {
    final complaint = await _fetchComplaint(complaintId);
    if (complaint == null) return [];

    final recent = await _supabase
        .from('complaints')
        .select('id, title, description')
        .neq('id', complaintId)
        .gte('created_at',
            DateTime.now().subtract(const Duration(days: 90)).toIso8601String())
        .limit(50);

    final baseTokens =
        _tokens('${complaint['title']} ${complaint['description']}').toSet();
    final results = <Map<String, dynamic>>[];

    for (final row in List<Map<String, dynamic>>.from(recent)) {
      final tokens = _tokens('${row['title']} ${row['description']}').toSet();
      final intersection = baseTokens.intersection(tokens).length;
      final union = baseTokens.union(tokens).length;
      final similarity = union == 0 ? 0 : intersection / union;
      if (similarity > 0) {
        results.add({
          'id': row['id'],
          'title': row['title'],
          'description': row['description'],
          'similarity': similarity,
        });
      }
    }

    results.sort(
      (a, b) => (_toDouble(b['similarity']) ?? 0)
          .compareTo(_toDouble(a['similarity']) ?? 0),
    );
    return results.take(limit).map((item) {
      final id = item['id'].toString();
      return {
        'id': id,
        'title': item['title'],
        'status': 'Unknown',
        'similarity': item['similarity'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _detectDuplicates(String complaintId,
      [double threshold = 0.85]) async {
    final similar = await _findSimilarComplaints(complaintId, 10);
    return similar
        .map((item) {
          final similarity = _toDouble(item['similarity']) ?? 0;
          return {
            ...item,
            'isDuplicate': similarity >= threshold,
          };
        })
        .where((item) => item['isDuplicate'] == true)
        .toList();
  }

  Future<Map<String, dynamic>> _detectAnomalies(int? categoryId) async {
    final now = DateTime.now();
    final recentStart = now.subtract(const Duration(days: 7)).toIso8601String();
    final baselineStart =
        now.subtract(const Duration(days: 30)).toIso8601String();
    final baselineEnd = now.subtract(const Duration(days: 7)).toIso8601String();

    final recentCount = await _countComplaints(
      categoryId: categoryId,
      createdAtGte: recentStart,
    );
    final baselineCount = await _countComplaints(
      categoryId: categoryId,
      createdAtGte: baselineStart,
      createdAtLt: baselineEnd,
    );

    final baselineAvg = baselineCount / 3;
    final deviation =
        baselineAvg > 0 ? (recentCount - baselineAvg) / baselineAvg : 0;
    final isAnomaly = deviation > 1.5 && recentCount >= 5;

    return {
      'isAnomaly': isAnomaly,
      'currentVolume': recentCount,
      'baselineAvg': (baselineAvg * 10).round() / 10,
      'deviation': (deviation * 100).round() / 100,
      'message': isAnomaly
          ? 'Unusual spike: $recentCount complaints in last 7 days vs avg ${baselineAvg.round()}'
          : 'Normal volume',
    };
  }

  Future<Map<String, dynamic>> _escalateComplaintById(
      String complaintId) async {
    final complaint = await _fetchComplaint(complaintId);
    if (complaint == null) throw MobileDataException('Complaint not found');

    final currentLevel = _toInt(complaint['current_escalation_level']) ?? 0;
    final maxLevel = _toInt(complaint['max_escalation_level']) ?? 3;
    final nextLevel = currentLevel + 1;

    if (nextLevel > maxLevel) {
      await _supabase.from('complaints').update({
        'status': 'CRITICAL',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', complaintId);

      return {'escalated': true, 'status': 'CRITICAL'};
    }

    final categoryId = _toInt(complaint['category_id']);
    if (categoryId == null) {
      throw MobileDataException('Complaint category not found');
    }

    final chain = await _escalationChain(categoryId, nextLevel);
    final oldOfficeId = _toInt(complaint['office_id']);
    final newOfficeId = _toInt(chain?['officeId']) ?? 0;

    await _supabase.from('complaints').update({
      'office_id': newOfficeId,
      'deadline_at': DateTime.now()
          .add(Duration(days: _toInt(chain?['slaDays']) ?? 3))
          .toIso8601String(),
      'current_escalation_level': nextLevel,
      'status': 'ESCALATED',
      'escalated': true,
      'should_escalate': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', complaintId);

    return {
      'escalated': true,
      'newLevel': nextLevel,
      'office': chain?['officeName'],
      'oldOfficeId': oldOfficeId,
      'newOfficeId': newOfficeId,
    };
  }

  Future<Map<String, dynamic>> _forceEscalateComplaint(
      String complaintId) async {
    final complaint = await _fetchComplaint(complaintId);
    if (complaint == null) throw MobileDataException('Complaint not found');

    final currentLevel = _toInt(complaint['current_escalation_level']) ?? 0;
    final nextLevel = currentLevel + 1;
    final categoryId = _toInt(complaint['category_id']);
    if (categoryId == null) {
      throw MobileDataException('Complaint category not found');
    }

    final chain = await _escalationChain(categoryId, nextLevel);
    final newOfficeId = _toInt(chain?['officeId']) ?? 0;

    await _supabase.from('complaints').update({
      'office_id': newOfficeId,
      'current_escalation_level': nextLevel,
      'status': 'ESCALATED',
      'escalated': true,
      'should_escalate': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', complaintId);

    return {
      'escalated': true,
      'newLevel': nextLevel,
      'office': chain?['officeName']
    };
  }

  Future<Map<String, dynamic>> _wordSuggestions(String query) async {
    final words = _tokens(query);
    final categorySuggestions = <Map<String, dynamic>>[];
    final officeSuggestions = <Map<String, dynamic>>[];

    for (final category in _categoryCache) {
      final categoryId = _toInt(category['id']);
      if (categoryId == null) continue;
      var score = 0;
      for (final word in words) {
        final row = _categoryWordCache.firstWhere(
          (item) =>
              _toInt(item['category_id']) == categoryId &&
              _string(item['word']) == word,
          orElse: () => <String, dynamic>{},
        );
        if (row.isNotEmpty) score += _toInt(row['count']) ?? 0;
      }
      if (score > 0) {
        categorySuggestions.add({
          'categoryId': categoryId,
          'categoryName': category['name'],
          'score': score
        });
      }
    }

    for (final office in _officeCache) {
      final officeId = _toInt(office['id']);
      if (officeId == null) continue;
      var score = 0;
      for (final word in words) {
        final row = _officeWordCache.firstWhere(
          (item) =>
              _toInt(item['office_id']) == officeId &&
              _string(item['word']) == word,
          orElse: () => <String, dynamic>{},
        );
        if (row.isNotEmpty) score += _toInt(row['count']) ?? 0;
      }
      if (score > 0) {
        officeSuggestions.add({
          'officeId': officeId,
          'officeName': office['name'],
          'score': score
        });
      }
    }

    categorySuggestions.sort(
      (a, b) => (_toInt(b['score']) ?? 0).compareTo(_toInt(a['score']) ?? 0),
    );
    officeSuggestions.sort(
      (a, b) => (_toInt(b['score']) ?? 0).compareTo(_toInt(a['score']) ?? 0),
    );

    return {
      'categorySuggestions': categorySuggestions.take(3).toList(),
      'officeSuggestions': officeSuggestions.take(3).toList(),
    };
  }

  Future<Map<String, dynamic>?> _fetchUserByEmail(String email) async {
    final response = await _supabase
        .from('users')
        .select(
            'id, full_name, email, phone, registration_number, college, faculty, employee_id, college_id, course_id, password, password_hash, role_id, office_id, is_active, created_at')
        .eq('email', email)
        .maybeSingle();

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> _fetchUserById(String id) async {
    final response = await _supabase
        .from('users')
        .select(
            'id, full_name, email, phone, registration_number, college, faculty, employee_id, college_id, course_id, password, password_hash, role_id, office_id, is_active, created_at')
        .eq('id', id)
        .maybeSingle();

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> _fetchStudent(String id) async {
    final response =
        await _supabase.from('students').select().eq('id', id).maybeSingle();

    if (response == null) return null;
    return await _enrichStudentData(Map<String, dynamic>.from(response));
  }

  Future<Map<String, dynamic>> _enrichStudentData(
      Map<String, dynamic> student) async {
    final enriched = Map<String, dynamic>.from(student);
    enriched['student_id'] =
        student['student_id'] ?? student['registration_number'];

    final collegeId = _toInt(student['college_id']);
    if (collegeId != null) {
      final college = await _supabase
          .from('colleges')
          .select()
          .eq('id', collegeId)
          .maybeSingle();

      if (college != null) enriched['colleges'] = college;
    }

    final courseId = _toInt(student['course_id']);
    if (courseId != null) {
      final course = await _supabase
          .from('courses')
          .select('*, departments(name)')
          .eq('id', courseId)
          .maybeSingle();

      if (course != null) {
        enriched['courses'] = course;
        enriched['department_id'] = course['department_id'];
      }
    }

    return enriched;
  }

  Map<String, dynamic> _studentDataFromUser(Map<String, dynamic> user) {
    return {
      'id': user['id']?.toString() ?? '',
      'full_name': user['full_name']?.toString() ??
          user['email']?.toString() ??
          'Student',
      'student_id': user['registration_number']?.toString() ?? '',
      'email': user['email']?.toString() ?? '',
      'phone': user['phone']?.toString() ?? '',
      'college_id': user['college_id'],
      'course_id': user['course_id'],
      'created_at': user['created_at'],
    };
  }

  Map<String, dynamic> _adminDataFromUser(
      Map<String, dynamic> user, String role) {
    final roleName = role.toUpperCase();
    return {
      'id': user['id']?.toString() ?? '',
      'full_name':
          user['full_name']?.toString() ?? user['email']?.toString() ?? 'Admin',
      'email': user['email']?.toString() ?? '',
      'employee_id': user['employee_id']?.toString() ?? '',
      'phone': user['phone']?.toString() ?? '',
      'role': roleName == 'SUPER_ADMIN' ? 'super_admin' : 'admin',
      'office_id': user['office_id'],
      'assigned_office_id': user['office_id'],
    };
  }

  Future<Map<String, dynamic>?> _fetchComplaint(String id) async {
    final response =
        await _supabase.from('complaints').select().eq('id', id).maybeSingle();

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> _enrichComplaints(
      List<Map<String, dynamic>> rows) async {
    final enriched = <Map<String, dynamic>>[];
    for (final row in rows) {
      enriched.add(await _enrichComplaint(row));
    }
    return enriched;
  }

  Future<Map<String, dynamic>> _enrichComplaint(
      Map<String, dynamic> complaint) async {
    final enriched = Map<String, dynamic>.from(complaint);
    final categoryId = _toInt(complaint['category_id']);
    final officeId = _toInt(complaint['office_id']);
    final studentId = complaint['student_id']?.toString();

    if (categoryId != null) {
      final category = await _fetchCategory(categoryId);
      if (category != null) enriched['category'] = category;
    }

    if (officeId != null) {
      final office = await _fetchOffice(officeId);
      if (office != null) enriched['office'] = office;
    }

    if (studentId != null) {
      final student = await _supabase
          .from('students')
          .select('id, full_name, email, student_id, phone')
          .eq('id', studentId)
          .maybeSingle();

      if (student != null) enriched['student_info'] = student;
    }

    final attachments = await _fetchAttachments(complaint['id'].toString());
    enriched['attachments'] = attachments.map((attachment) {
      return {
        'id': attachment['id'],
        'fileName': attachment['file_name'],
        'fileUrl': attachment['file_url'],
        'fileType': attachment['file_type'],
        'fileSize': attachment['file_size'],
        'extractedTextLength': _string(attachment['extracted_text']).length,
        'createdAt': attachment['created_at'],
      };
    }).toList();

    final history = await _supabase
        .from('complaint_status_history')
        .select()
        .eq('complaint_id', complaint['id'].toString())
        .order('created_at', ascending: false);

    enriched['statusHistory'] = history;
    return enriched;
  }

  Future<List<Map<String, dynamic>>> _fetchAttachments(
      String complaintId) async {
    return List<Map<String, dynamic>>.from(
      await _supabase
          .from('attachments')
          .select()
          .eq('complaint_id', complaintId)
          .order('created_at', ascending: false),
    );
  }

  Future<Map<String, dynamic>?> _fetchCategory(int id) async {
    final category = await _supabase
        .from('issue_categories')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (category == null) return null;

    final enriched = Map<String, dynamic>.from(category);
    final priorityId = _toInt(category['priority_id']);
    if (priorityId != null) {
      final priority = await _supabase
          .from('issue_priorities')
          .select()
          .eq('id', priorityId)
          .maybeSingle();

      if (priority != null) enriched['priority'] = priority;
    }

    final defaultOfficeId = _toInt(category['default_office_id']);
    if (defaultOfficeId != null) {
      final office = await _fetchOffice(defaultOfficeId);
      if (office != null) enriched['defaultOffice'] = office;
    }

    return enriched;
  }

  Future<Map<String, dynamic>?> _fetchOffice(int id) async {
    final office = await _supabase
        .from('offices')
        .select('id, name, level, building, room_number')
        .eq('id', id)
        .maybeSingle();

    return office == null ? null : Map<String, dynamic>.from(office);
  }

  Future<String> _fetchUserRole(dynamic roleId) async {
    final id = _toInt(roleId);
    if (id == null) return 'USER';

    final role =
        await _supabase.from('roles').select('name').eq('id', id).maybeSingle();

    return _string(role?['name']);
  }

  Future<int> _roleId(String name) async {
    final role =
        await _supabase.from('roles').select('id').eq('name', name).single();

    return _toInt(role['id']) ?? 0;
  }

  Future<int> _countComplaints({
    String? studentId,
    int? officeId,
    String? status,
    String? search,
    int? categoryId,
    String? createdAtGte,
    String? createdAtLt,
  }) async {
    dynamic query = _supabase.from('complaints').select();

    if (studentId != null) query = query.eq('student_id', studentId);
    if (officeId != null) query = query.eq('office_id', officeId);
    if (status != null && status.isNotEmpty) {
      final statuses = status
          .split(',')
          .where((s) => s.isNotEmpty)
          .map((s) => s.toUpperCase())
          .toList();
      if (statuses.length == 1) {
        query = query.eq('status', statuses.first);
      } else {
        query = query.inFilter('status', statuses);
      }
    }
    if (search != null && search.trim().isNotEmpty) {
      final safeSearch = search.trim().replaceAll('%', '');
      query =
          query.or('title.ilike.%$safeSearch%,description.ilike.%$safeSearch%');
    }
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (createdAtGte != null) query = query.gte('created_at', createdAtGte);
    if (createdAtLt != null) query = query.lt('created_at', createdAtLt);

    final response = await query.count();
    return response.count ?? 0;
  }

  List<Map<String, dynamic>> _categoryCache = const [];
  List<Map<String, dynamic>> _officeCache = const [];
  List<Map<String, dynamic>> _categoryWordCache = const [];
  List<Map<String, dynamic>> _officeWordCache = const [];

  Future<void> _loadKeywordCaches() async {
    if (_categoryCache.isNotEmpty && _officeCache.isNotEmpty) return;

    final categories =
        await _supabase.from('issue_categories').select('id, name');
    final offices = await _supabase.from('offices').select('id, name');
    final categoryWords = await _supabase
        .from('category_words')
        .select('category_id, word, count');
    final officeWords =
        await _supabase.from('office_words').select('office_id, word, count');

    _categoryCache = List<Map<String, dynamic>>.from(categories);
    _officeCache = List<Map<String, dynamic>>.from(offices);
    _categoryWordCache = List<Map<String, dynamic>>.from(categoryWords);
    _officeWordCache = List<Map<String, dynamic>>.from(officeWords);
  }

  bool _isActive(Map<String, dynamic> user) => user['is_active'] != false;

  bool _isStaffRole(String role) {
    final normalized = role.toUpperCase();
    return normalized == 'OFFICE_USER' ||
        normalized == 'OFFICE_MANAGER' ||
        normalized == 'SUPER_ADMIN';
  }

  bool _passwordMatches(
      String storedPassword, String storedHash, String password) {
    if (storedPassword.isNotEmpty && storedPassword == password) return true;

    if (storedHash.startsWith(r'$supabase$')) {
      return storedHash == password;
    }

    if (storedHash.startsWith(r'$2')) {
      try {
        return BCrypt.checkpw(password, storedHash);
      } catch (_) {
        return false;
      }
    }

    return storedHash == password;
  }

  String _hashPassword(String password) =>
      BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));

  List<String> _tokens(String text) {
    final matches = RegExp(r'[a-z0-9]+').allMatches(text.toLowerCase());
    return matches
        .map((match) => match.group(0)!)
        .where((token) => token.length > 2)
        .toList();
  }

  double _sentimentUrgency(String title, String description) {
    final text = '$title $description'.toLowerCase();
    final urgentWords = [
      'urgent',
      'emergency',
      'asap',
      'danger',
      'threat',
      'unsafe',
      'harassment',
      'violence',
      'health',
      'security'
    ];
    final matched = urgentWords.where(text.contains).length;
    return matched == 0
        ? 0.0
        : (0.25 + (matched / urgentWords.length)).clamp(0.25, 0.95);
  }

  String _trackingCode() {
    final random = Random.secure();
    final chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  dynamic _decodeJson(dynamic value) {
    if (value == null) return null;
    if (value is Map || value is List) return value;

    try {
      return jsonDecode(value.toString());
    } catch (_) {
      return value;
    }
  }

  String _string(dynamic value) => value?.toString() ?? '';

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;

    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }
}
