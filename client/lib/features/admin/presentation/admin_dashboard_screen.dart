import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _users = [];
  bool _isLoadingCourses = true;
  bool _isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCourses();
    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    try {
      final data = await ref.read(apiClientProvider).listCourses();
      setState(() {
        _courses = List<Map<String, dynamic>>.from(data['content'] ?? []);
        _isLoadingCourses = false;
      });
    } catch (_) {
      setState(() => _isLoadingCourses = false);
    }
  }

  Future<void> _loadUsers() async {
    try {
      final data = await ref.read(apiClientProvider).listUsers();
      setState(() {
        _users = List<Map<String, dynamic>>.from(data['content'] ?? []);
        _isLoadingUsers = false;
      });
    } catch (_) {
      setState(() => _isLoadingUsers = false);
    }
  }

  void _showCreateCourseDialog() {
    final codeController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Course'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Course Code (e.g. CS201)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Course Name'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(apiClientProvider).createCourse(
                  code: codeController.text,
                  name: nameController.text,
                );
                _loadCourses();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authStateProvider.notifier).logout();
              context.go('/login');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.book), text: 'Courses'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateCourseDialog,
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Courses tab
          _isLoadingCourses
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadCourses,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _courses.length,
                    itemBuilder: (context, index) {
                      final course = _courses[index];
                      return Card(
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.book, color: AppTheme.primaryColor),
                          ),
                          title: Text(course['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(course['name'] ?? ''),
                        ),
                      );
                    },
                  ),
                ),

          // Users tab
          _isLoadingUsers
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final role = user['role'] ?? 'UNKNOWN';
                      final roleColor = switch (role) {
                        'STUDENT' => AppTheme.primaryColor,
                        'FACULTY' => AppTheme.secondaryColor,
                        'ADMIN' => AppTheme.warningColor,
                        _ => Colors.grey,
                      };
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: roleColor.withOpacity(0.1),
                            child: Icon(Icons.person, color: roleColor),
                          ),
                          title: Text(user['fullName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(user['email'] ?? ''),
                          trailing: Chip(
                            label: Text(role, style: TextStyle(color: roleColor, fontSize: 11)),
                            backgroundColor: roleColor.withOpacity(0.1),
                            side: BorderSide.none,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
