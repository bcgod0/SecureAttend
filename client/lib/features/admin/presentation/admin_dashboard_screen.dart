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
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentTab = _tabController.index);
    });
    _loadCourses();
    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoadingCourses = true);
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
    setState(() => _isLoadingUsers = true);
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

  // ── Stats ──────────────────────────────────────────────────────────────────
  int get _studentCount => _users.where((u) => u['role'] == 'STUDENT').length;
  int get _facultyCount => _users.where((u) => u['role'] == 'FACULTY').length;

  // ── Create Course Dialog ───────────────────────────────────────────────────
  void _showCreateCourseDialog() {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Create Course'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Course Code',
                  hintText: 'e.g. CS501',
                  prefixIcon: Icon(Icons.tag),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Code is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Course Name',
                  hintText: 'e.g. Machine Learning',
                  prefixIcon: Icon(Icons.book_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              try {
                await ref.read(apiClientProvider).createCourse(
                  code: codeController.text.trim().toUpperCase(),
                  name: nameController.text.trim(),
                );
                _loadCourses();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Course created!'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                }
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

  // ── Enroll Students Dialog ─────────────────────────────────────────────────
  void _showEnrollDialog(Map<String, dynamic> course) {
    final students = _users.where((u) => u['role'] == 'STUDENT').toList();
    final selected = <String>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enroll Students', style: Theme.of(ctx).textTheme.titleLarge),
              Text(
                '${course['code']} — ${course['name']}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: students.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No students registered yet.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: students.length,
                    itemBuilder: (_, i) {
                      final s = students[i];
                      final id = s['id'] as String;
                      return CheckboxListTile(
                        value: selected.contains(id),
                        onChanged: (v) => setS(() {
                          v == true ? selected.add(id) : selected.remove(id);
                        }),
                        title: Text(s['fullName'] ?? ''),
                        subtitle: Text(s['email'] ?? ''),
                        activeColor: AppTheme.primaryColor,
                        dense: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      try {
                        await ref.read(apiClientProvider).enrollStudents(
                          course['id'] as String,
                          selected.toList(),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${selected.length} student(s) enrolled!'),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
                          );
                        }
                      }
                    },
              child: Text('Enroll (${selected.length})'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);

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
            tooltip: 'Logout',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.book_outlined),
              text: 'Courses (${_courses.length})',
            ),
            Tab(
              icon: const Icon(Icons.people_outline),
              text: 'Users (${_users.length})',
            ),
          ],
        ),
      ),

      // FAB changes label based on tab
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _currentTab == 0 ? _showCreateCourseDialog : null,
        backgroundColor: _currentTab == 0 ? AppTheme.primaryColor : Colors.grey,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          _currentTab == 0 ? 'New Course' : 'Users via Register',
          style: const TextStyle(color: Colors.white),
        ),
      ),

      body: Column(
        children: [
          // ── Stats header ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.book,
                  label: 'Courses',
                  value: '${_courses.length}',
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.school,
                  label: 'Students',
                  value: '$_studentCount',
                  color: AppTheme.secondaryColor,
                ),
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.person,
                  label: 'Faculty',
                  value: '$_facultyCount',
                  color: AppTheme.accentColor,
                ),
                const Spacer(),
                // Admin name
                Text(
                  authState.fullName ?? 'Admin',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Tab content ─────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCoursesTab(),
                _buildUsersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Courses Tab ────────────────────────────────────────────────────────────
  Widget _buildCoursesTab() {
    if (_isLoadingCourses) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No courses yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Tap + to create your first course', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCourses,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _courses.length,
        itemBuilder: (context, index) {
          final course = _courses[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showEnrollDialog(course),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryColor, Color(0xFF8B7CF7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          (course['code'] as String? ?? '?').substring(0, 1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course['code'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            course['name'] ?? '',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Enroll students',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_outlined, size: 14, color: AppTheme.primaryColor),
                            SizedBox(width: 4),
                            Text('Enroll', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Users Tab ──────────────────────────────────────────────────────────────
  Widget _buildUsersTab() {
    if (_isLoadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No users yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Users register at /register', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Group by role
    final students = _users.where((u) => u['role'] == 'STUDENT').toList();
    final faculty = _users.where((u) => u['role'] == 'FACULTY').toList();
    final admins = _users.where((u) => u['role'] == 'ADMIN').toList();

    final sections = [
      if (admins.isNotEmpty) ('Admins', admins, AppTheme.warningColor),
      if (faculty.isNotEmpty) ('Faculty', faculty, AppTheme.secondaryColor),
      if (students.isNotEmpty) ('Students', students, AppTheme.primaryColor),
    ];

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (sectionTitle, users, color) in sections) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$sectionTitle (${users.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            ...users.map((user) => _UserCard(user: user, roleColor: color)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ─── Stat Chip ────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
              Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── User Card ────────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final Color roleColor;

  const _UserCard({required this.user, required this.roleColor});

  @override
  Widget build(BuildContext context) {
    final name = user['fullName'] as String? ?? '';
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: roleColor.withValues(alpha: 0.15),
          child: Text(
            initials,
            style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(user['email'] as String? ?? '', style: const TextStyle(fontSize: 12)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: roleColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            (user['role'] as String? ?? '').toLowerCase(),
            style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
