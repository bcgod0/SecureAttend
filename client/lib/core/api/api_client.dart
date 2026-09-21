import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String get defaultBaseUrl {
  const envUrl = String.fromEnvironment('API_BASE_URL');
  if (envUrl.isNotEmpty) return envUrl;
  if (kIsWeb) {
    final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
    final scheme = Uri.base.scheme.isNotEmpty ? Uri.base.scheme : 'http';
    return '$scheme://$host:8080/api';
  }
  return 'http://localhost:8080/api';
}

String get defaultWsUrl {
  const envWs = String.fromEnvironment('WS_URL');
  if (envWs.isNotEmpty) return envWs;
  if (kIsWeb) {
    final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
    final wsScheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://$host:8080/ws';
  }
  return 'ws://localhost:8080/ws';
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: defaultBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to refresh token
          final refreshed = await _refreshToken();
          if (refreshed) {
            // Retry the failed request
            final opts = error.requestOptions;
            final token = await _storage.read(key: 'access_token');
            opts.headers['Authorization'] = 'Bearer $token';
            final response = await _dio.fetch(opts);
            handler.resolve(response);
            return;
          }
        }
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;

      final response = await Dio(BaseOptions(baseUrl: defaultBaseUrl)).post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      final newAccessToken = response.data['accessToken'];
      await _storage.write(key: 'access_token', value: newAccessToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- Auth ----

  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
    required String role,
    String? branch,
    String? section,
    String? rollNo,
    String? fatherName,
    int? semester,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'email': email,
      'username': username,
      'password': password,
      'fullName': fullName,
      'role': role,
      if (branch != null) 'branch': branch,
      if (section != null) 'section': section,
      if (rollNo != null) 'rollNo': rollNo,
      if (fatherName != null) 'fatherName': fatherName,
      if (semester != null) 'semester': semester,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });

    // Store tokens
    await _storage.write(key: 'access_token', value: response.data['accessToken']);
    await _storage.write(key: 'refresh_token', value: response.data['refreshToken']);

    return response.data;
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get('/auth/me');
    return response.data;
  }

  // ---- Enrollment ----

  Future<Map<String, dynamic>> enrollFace(List<int> imageBytes, String filename) async {
    final formData = FormData.fromMap({
      'faceImage': MultipartFile.fromBytes(imageBytes, filename: filename),
    });
    final response = await _dio.post('/enrollment/face', data: formData);
    return response.data;
  }

  Future<Map<String, dynamic>> registerDevice({
    required String fingerprintHash,
    Map<String, String>? deviceInfo,
  }) async {
    final response = await _dio.post('/enrollment/device', data: {
      'fingerprintHash': fingerprintHash,
      'deviceInfo': deviceInfo,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> replaceDevice({
    required String fingerprintHash,
    Map<String, String>? deviceInfo,
  }) async {
    final response = await _dio.put('/enrollment/device', data: {
      'fingerprintHash': fingerprintHash,
      'deviceInfo': deviceInfo,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> getEnrollmentStatus() async {
    final response = await _dio.get('/enrollment/status');
    return response.data;
  }

  // ---- Sessions ----

  Future<Map<String, dynamic>> createSession({
    required String courseId,
    required double geofenceLat,
    required double geofenceLon,
    required int geofenceRadiusMeters,
    int qrRotationSeconds = 10,
  }) async {
    final response = await _dio.post('/sessions', data: {
      'courseId': courseId,
      'geofenceLat': geofenceLat,
      'geofenceLon': geofenceLon,
      'geofenceRadiusMeters': geofenceRadiusMeters,
      'qrRotationSeconds': qrRotationSeconds,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> closeSession(String sessionId) async {
    final response = await _dio.patch('/sessions/$sessionId/close');
    return response.data;
  }

  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final response = await _dio.get('/sessions/$sessionId');
    return response.data;
  }

  Future<Map<String, dynamic>> listSessions({String? status, int page = 0}) async {
    final params = <String, dynamic>{'page': page, 'size': 20};
    if (status != null) params['status'] = status;
    final response = await _dio.get('/sessions', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> getAttendance(String sessionId, {String? status, int page = 0}) async {
    final params = <String, dynamic>{'page': page, 'size': 50};
    if (status != null) params['status'] = status;
    final response = await _dio.get('/sessions/$sessionId/attendance', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> getCurrentQrToken(String sessionId) async {
    final response = await _dio.get('/sessions/$sessionId/qr-token');
    return response.data;
  }

  // ---- Scan ----

  Future<Map<String, dynamic>> verifyScan({
    required String qrToken,
    required String deviceFingerprint,
    required double latitude,
    required double longitude,
    required List<int> faceFrameBytes,
  }) async {
    final formData = FormData.fromMap({
      'qrToken': qrToken,
      'deviceFingerprint': deviceFingerprint,
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'faceFrame': MultipartFile.fromBytes(faceFrameBytes, filename: 'face.jpg'),
    });
    final response = await _dio.post('/scan/verify', data: formData);
    return response.data;
  }

  Future<List<Map<String, dynamic>>> getMyAttendanceHistory() async {
    final response = await _dio.get('/scan/my-history');
    return List<Map<String, dynamic>>.from(response.data ?? []);
  }

  // ---- Review ----

  Future<Map<String, dynamic>> getReviewQueue({String? sessionId, int page = 0}) async {
    final params = <String, dynamic>{'page': page, 'size': 20};
    if (sessionId != null) params['sessionId'] = sessionId;
    final response = await _dio.get('/review/queue', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> reviewScan(String scanId, {
    required String decision,
    String? notes,
  }) async {
    final response = await _dio.patch('/review/$scanId', data: {
      'decision': decision,
      if (notes != null) 'notes': notes,
    });
    return response.data;
  }

  // ---- Admin ----

  Future<Map<String, dynamic>> createCourse({
    required String code,
    required String name,
    String? branch,
    int? year,
    int? semester,
    String? facultyId,
    String? academicSession,
    String? courseType,
    int? credits,
    bool isActive = true,
  }) async {
    final response = await _dio.post('/admin/courses', data: {
      'code': code,
      'name': name,
      if (branch != null && branch.isNotEmpty) 'branch': branch,
      if (year != null) 'year': year,
      if (semester != null) 'semester': semester,
      if (facultyId != null && facultyId.isNotEmpty) 'facultyId': facultyId,
      if (academicSession != null && academicSession.isNotEmpty) 'academicSession': academicSession,
      if (courseType != null && courseType.isNotEmpty) 'courseType': courseType,
      if (credits != null) 'credits': credits,
      'isActive': isActive,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> updateCourse(
    String courseId, {
    String? code,
    String? name,
    String? branch,
    int? year,
    int? semester,
    String? facultyId,
    String? academicSession,
    String? courseType,
    int? credits,
    bool? isActive,
  }) async {
    final response = await _dio.put('/admin/courses/$courseId', data: {
      if (code != null && code.isNotEmpty) 'code': code,
      if (name != null && name.isNotEmpty) 'name': name,
      if (branch != null) 'branch': branch,
      if (year != null) 'year': year,
      if (semester != null) 'semester': semester,
      if (facultyId != null) 'facultyId': facultyId,
      if (academicSession != null) 'academicSession': academicSession,
      if (courseType != null) 'courseType': courseType,
      if (credits != null) 'credits': credits,
      if (isActive != null) 'isActive': isActive,
    });
    return response.data;
  }

  Future<void> deleteCourse(String courseId) async {
    await _dio.delete('/admin/courses/$courseId');
  }

  Future<Map<String, dynamic>> listCourses({
    String? search,
    String? branch,
    String? facultyId,
    int? semester,
    String? academicSession,
    bool? isActive,
    int page = 0,
    int size = 50,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (branch != null && branch.isNotEmpty) params['branch'] = branch;
    if (facultyId != null && facultyId.isNotEmpty) params['facultyId'] = facultyId;
    if (semester != null) params['semester'] = semester;
    if (academicSession != null && academicSession.isNotEmpty) params['academicSession'] = academicSession;
    if (isActive != null) params['isActive'] = isActive;
    final response = await _dio.get('/admin/courses', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> listUsers({
    String? role,
    String? status,
    String? branch,
    int? semester,
    String? search,
    int page = 0,
    int size = 100,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (role != null && role.isNotEmpty) params['role'] = role;
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (branch != null && branch.isNotEmpty) params['branch'] = branch;
    if (semester != null) params['semester'] = semester;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final response = await _dio.get('/admin/users', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> enrollStudents(String courseId, List<String> studentIds) async {
    final response = await _dio.post('/admin/courses/$courseId/enroll', data: {
      'studentIds': studentIds,
    });
    return response.data;
  }

  Future<List<Map<String, dynamic>>> listCourseStudents(String courseId) async {
    final response = await _dio.get('/admin/courses/$courseId/students');
    return List<Map<String, dynamic>>.from(response.data ?? []);
  }

  Future<void> unenrollStudent(String courseId, String studentId) async {
    await _dio.delete('/admin/courses/$courseId/enroll/$studentId');
  }

  Future<Map<String, dynamic>> getBulkEnrollPreview(String courseId) async {
    final response = await _dio.get('/admin/courses/$courseId/enroll-preview');
    return response.data;
  }

  Future<Map<String, dynamic>> bulkEnrollBranch(String courseId) async {
    final response = await _dio.post('/admin/courses/$courseId/enroll-branch');
    return response.data;
  }

  Future<Map<String, dynamic>> createUser({
    required String email,
    String? username,
    required String password,
    required String fullName,
    required String role,
    String? branch,
    String? section,
    String? rollNo,
    String? fatherName,
    int? semester,
  }) async {
    final response = await _dio.post('/admin/users', data: {
      'email': email,
      if (username != null && username.isNotEmpty) 'username': username,
      'password': password,
      'fullName': fullName,
      'role': role,
      if (branch != null && branch.isNotEmpty) 'branch': branch,
      if (section != null && section.isNotEmpty) 'section': section,
      if (rollNo != null && rollNo.isNotEmpty) 'rollNo': rollNo,
      if (fatherName != null && fatherName.isNotEmpty) 'fatherName': fatherName,
      if (semester != null) 'semester': semester,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> updateUser(
    String userId, {
    String? fullName,
    String? username,
    String? email,
    String? branch,
    String? section,
    String? rollNo,
    String? fatherName,
    int? semester,
  }) async {
    final response = await _dio.put('/admin/users/$userId', data: {
      if (fullName != null) 'fullName': fullName,
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      if (branch != null) 'branch': branch,
      if (section != null) 'section': section,
      if (rollNo != null) 'rollNo': rollNo,
      if (fatherName != null) 'fatherName': fatherName,
      if (semester != null) 'semester': semester,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> setUserStatus(String userId, String status) async {
    final response = await _dio.patch('/admin/users/$userId/status', data: {'status': status});
    return response.data;
  }

  Future<void> deleteUser(String userId) async {
    await _dio.delete('/admin/users/$userId');
  }

  Future<Map<String, dynamic>> listPendingUsers({int page = 0}) async {
    final params = <String, dynamic>{'page': page, 'size': 50, 'status': 'PENDING'};
    final response = await _dio.get('/admin/users', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> approveUser(String userId) async {
    final response = await _dio.patch('/admin/users/$userId/approve');
    return response.data;
  }

  Future<void> rejectUser(String userId) async {
    await _dio.delete('/admin/users/$userId/reject');
  }
}
