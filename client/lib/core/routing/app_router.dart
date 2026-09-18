import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/enrollment/presentation/enrollment_screen.dart';
import '../../features/scan/presentation/scan_screen.dart';
import '../../features/session/presentation/create_session_screen.dart';
import '../../features/session/presentation/session_dashboard_screen.dart';
import '../../features/display_mode/presentation/display_mode_screen.dart';
import '../../features/review/presentation/review_queue_screen.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../api/api_client.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.isLoggedIn;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) {
        switch (authState.role) {
          case 'STUDENT':
            return '/student/scan';
          case 'FACULTY':
            return '/faculty/sessions';
          case 'ADMIN':
            return '/admin';
          default:
            return '/login';
        }
      }
      return null;
    },
    routes: [
      // ---- Auth ----
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // ---- Student ----
      GoRoute(
        path: '/student/enrollment',
        builder: (context, state) => const EnrollmentScreen(),
      ),
      GoRoute(
        path: '/student/scan',
        builder: (context, state) => const ScanScreen(),
      ),

      // ---- Faculty ----
      GoRoute(
        path: '/faculty/sessions',
        builder: (context, state) => const SessionDashboardScreen(),
      ),
      GoRoute(
        path: '/faculty/sessions/create',
        builder: (context, state) => const CreateSessionScreen(),
      ),
      GoRoute(
        path: '/faculty/display/:sessionId',
        builder: (context, state) => DisplayModeScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      GoRoute(
        path: '/faculty/review',
        builder: (context, state) => const ReviewQueueScreen(),
      ),

      // ---- Admin ----
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
    ],
  );
});
