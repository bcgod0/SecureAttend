import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class SessionDashboardScreen extends ConsumerStatefulWidget {
  const SessionDashboardScreen({super.key});

  @override
  ConsumerState<SessionDashboardScreen> createState() => _SessionDashboardScreenState();
}

class _SessionDashboardScreenState extends ConsumerState<SessionDashboardScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final data = await ref.read(apiClientProvider).listSessions();
      setState(() {
        _sessions = List<Map<String, dynamic>>.from(data['content'] ?? []);
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rate_review_outlined),
            onPressed: () => context.go('/faculty/review'),
            tooltip: 'Review Queue',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authStateProvider.notifier).logout();
              context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/faculty/sessions/create'),
        icon: const Icon(Icons.add),
        label: const Text('New Session'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_note, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('No sessions yet', style: TextStyle(color: Colors.grey.shade600, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text('Create a session to start taking attendance'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final isActive = session['status'] == 'ACTIVE';
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppTheme.successColor.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isActive ? Icons.play_circle : Icons.stop_circle,
                              color: isActive ? AppTheme.successColor : Colors.grey,
                            ),
                          ),
                          title: Text(
                            '${session['courseCode']} — ${session['courseName']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${session['status']} · ${session['attendanceCount'] ?? 0} scans',
                          ),
                          trailing: isActive
                              ? ElevatedButton.icon(
                                  icon: const Icon(Icons.tv, size: 16),
                                  label: const Text('Display'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.secondaryColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () => context.go('/faculty/display/${session['id']}'),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
