import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api',
);

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
      baseUrl: baseUrl,
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

      final response = await Dio(BaseOptions(baseUrl: baseUrl)).post(
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

  Future<Map<String, dynamic>> createCourse({required String code, required String name}) async {
    final response = await _dio.post('/admin/courses', data: {'code': code, 'name': name});
    return response.data;
  }

  Future<Map<String, dynamic>> listCourses({String? search, int page = 0}) async {
    final params = <String, dynamic>{'page': page, 'size': 20};
    if (search != null) params['search'] = search;
    final response = await _dio.get('/admin/courses', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> listUsers({String? role, String? search, int page = 0}) async {
    final params = <String, dynamic>{'page': page, 'size': 20};
    if (role != null) params['role'] = role;
    if (search != null) params['search'] = search;
    final response = await _dio.get('/admin/users', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> enrollStudents(String courseId, List<String> studentIds) async {
    final response = await _dio.post('/admin/courses/$courseId/enroll', data: {
      'studentIds': studentIds,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final response = await _dio.post('/admin/users', data: {
      'email': email,
      'password': password,
      'fullName': fullName,
      'role': role,
    });
    return response.data;
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
