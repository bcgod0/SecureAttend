import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/api/api_client.dart';

class AuthState {
  final bool isLoggedIn;
  final String? userId;
  final String? email;
  final String? fullName;
  final String? role;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.userId,
    this.email,
    this.fullName,
    this.role,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    String? userId,
    String? email,
    String? fullName,
    String? role,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;

  AuthNotifier(this._apiClient, this._storage) : super(const AuthState()) {
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final token = await _storage.read(key: 'access_token');
    final role = await _storage.read(key: 'user_role');
    final userId = await _storage.read(key: 'user_id');
    final email = await _storage.read(key: 'user_email');
    final fullName = await _storage.read(key: 'user_name');

    if (token != null && role != null) {
      state = state.copyWith(
        isLoggedIn: true,
        userId: userId,
        email: email,
        fullName: fullName,
        role: role,
      );
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _apiClient.login(email: email, password: password);
      final user = data['user'];

      await _storage.write(key: 'user_id', value: user['id']);
      await _storage.write(key: 'user_email', value: user['email']);
      await _storage.write(key: 'user_name', value: user['fullName']);
      await _storage.write(key: 'user_role', value: user['role']);

      state = state.copyWith(
        isLoggedIn: true,
        userId: user['id'],
        email: user['email'],
        fullName: user['fullName'],
        role: user['role'],
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Login failed. Please check your credentials.',
      );
      return false;
    }
  }

  Future<bool> register(String email, String password, String fullName, String role) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _apiClient.register(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
      );
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Registration failed. Email may already be registered.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _apiClient.logout();
    await _storage.deleteAll();
    state = const AuthState();
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  const storage = FlutterSecureStorage();
  return AuthNotifier(apiClient, storage);
});
