import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  List<Map<String, dynamic>> _pendingUsers = [];
  bool _isLoadingCourses = true;
  bool _isLoadingUsers = true;
  bool _isLoadingPending = true;
  int _currentTab = 0;

  // Filter states
  String _courseSearch = '';
  String? _courseBranchFilter;

  final _userSearchController = TextEditingController();
  String _userSearchQuery = '';
  String _userRoleFilter = 'ALL'; // ALL, STUDENT, FACULTY, ADMIN
  String _userStatusFilter = 'ALL'; // ALL, ACTIVE, DEACTIVATED, PENDING
  String? _userBranchFilter;

  static const List<String> _branches = [
    'CSE',
    'CS',
    'CSE-AI',
    'CSE-AIML',
    'IT',
    'ECE',
    'EN',
    'ME',
    'CE',
    'MCA',
    'MTech',
  ];

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
    _loadPendingUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSearchController.dispose();
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

  Future<void> _loadPendingUsers() async {
    setState(() => _isLoadingPending = true);
    try {
      final data = await ref.read(apiClientProvider).listPendingUsers();
      setState(() {
        _pendingUsers = List<Map<String, dynamic>>.from(data['content'] ?? []);
        _isLoadingPending = false;
      });
    } catch (_) {
      setState(() => _isLoadingPending = false);
    }
  }

  Future<void> _approveUser(Map<String, dynamic> user) async {
    try {
      await ref.read(apiClientProvider).approveUser(user['id'] as String);
      await Future.wait([_loadPendingUsers(), _loadUsers()]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['fullName']} approved successfully!'),
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
  }

  Future<void> _rejectUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Registration'),
        content: Text(
          'Reject and delete the account for "${user['fullName']}" (${user['email']})? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject & Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).rejectUser(user['id'] as String);
      await _loadPendingUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['fullName']} registration has been rejected.'),
            backgroundColor: AppTheme.warningColor,
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
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  int get _studentCount => _users.where((u) => u['role'] == 'STUDENT' && u['status'] == 'ACTIVE').length;
  int get _facultyCount => _users.where((u) => u['role'] == 'FACULTY' && u['status'] == 'ACTIVE').length;

  // ── Create Course Dialog ───────────────────────────────────────────────────
  void _showCreateCourseDialog() {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final sessionController = TextEditingController(text: '2024-2025');
    final creditsController = TextEditingController(text: '4');

    String? selectedBranch = 'CSE';
    int selectedYear = 1;
    int selectedSemester = 1;
    String? selectedFacultyId;
    String selectedCourseType = 'CORE';
    bool isActive = true;

    final formKey = GlobalKey<FormState>();
    final facultyList = _users.where((u) => u['role'] == 'FACULTY' && u['status'] == 'ACTIVE').toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: codeController,
                            decoration: const InputDecoration(
                              labelText: 'Course Code',
                              hintText: 'e.g. CS501',
                              prefixIcon: Icon(Icons.tag),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Course Name',
                              hintText: 'e.g. Operating Systems',
                              prefixIcon: Icon(Icons.book_outlined),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Branch Dropdown
                    DropdownButtonFormField<String>(
                      value: selectedBranch,
                      decoration: const InputDecoration(
                        labelText: 'Branch / Department',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                      onChanged: (val) => setDialogState(() => selectedBranch = val),
                    ),
                    const SizedBox(height: 14),

                    // Year & Semester
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selectedYear,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                              prefixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                            items: [1, 2, 3, 4]
                                .map((y) => DropdownMenuItem(value: y, child: Text('Year $y')))
                                .toList(),
                            onChanged: (val) => setDialogState(() => selectedYear = val ?? 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selectedSemester,
                            decoration: const InputDecoration(
                              labelText: 'Semester',
                              prefixIcon: Icon(Icons.school_outlined),
                            ),
                            items: [1, 2, 3, 4, 5, 6, 7, 8]
                                .map((s) => DropdownMenuItem(value: s, child: Text('Sem $s')))
                                .toList(),
                            onChanged: (val) => setDialogState(() => selectedSemester = val ?? 1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Assigned Faculty
                    DropdownButtonFormField<String?>(
                      value: selectedFacultyId,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Faculty',
                        prefixIcon: Icon(Icons.person_pin_outlined),
                        helperText: 'Only the assigned faculty can conduct attendance',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Unassigned / None'),
                        ),
                        ...facultyList.map((f) => DropdownMenuItem<String?>(
                          value: f['id'] as String,
                          child: Text('${f['fullName']} (${f['email']})', overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: (val) => setDialogState(() => selectedFacultyId = val),
                    ),
                    const SizedBox(height: 14),

                    // Academic Session & Course Type
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: sessionController,
                            decoration: const InputDecoration(
                              labelText: 'Academic Session',
                              hintText: 'e.g. 2024-2025',
                              prefixIcon: Icon(Icons.access_time_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedCourseType,
                            decoration: const InputDecoration(
                              labelText: 'Course Type',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: ['CORE', 'ELECTIVE', 'LAB', 'SEMINAR']
                                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                .toList(),
                            onChanged: (val) => setDialogState(() => selectedCourseType = val ?? 'CORE'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Credits & Active Status
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: creditsController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Credits',
                              hintText: 'e.g. 4',
                              prefixIcon: Icon(Icons.stars_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active Course', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(isActive ? 'Can conduct sessions' : 'Sessions disabled', style: const TextStyle(fontSize: 11)),
                            value: isActive,
                            activeColor: AppTheme.successColor,
                            onChanged: (val) => setDialogState(() => isActive = val),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                    branch: selectedBranch,
                    year: selectedYear,
                    semester: selectedSemester,
                    facultyId: selectedFacultyId,
                    academicSession: sessionController.text.trim(),
                    courseType: selectedCourseType,
                    credits: int.tryParse(creditsController.text.trim()),
                    isActive: isActive,
                  );
                  _loadCourses();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Course created successfully!'),
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
              child: const Text('Create Course'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit Course Dialog ─────────────────────────────────────────────────────
  void _showEditCourseDialog(Map<String, dynamic> course) {
    final codeController = TextEditingController(text: course['code'] as String? ?? '');
    final nameController = TextEditingController(text: course['name'] as String? ?? '');
    final sessionController = TextEditingController(text: course['academicSession'] as String? ?? '2024-2025');
    final creditsController = TextEditingController(text: (course['credits'] ?? '4').toString());

    String? selectedBranch = course['branch'] as String?;
    if (selectedBranch != null && !_branches.contains(selectedBranch)) {
      selectedBranch = null;
    }
    int selectedYear = course['year'] as int? ?? 1;
    int selectedSemester = course['semester'] as int? ?? 1;
    String? selectedFacultyId = course['facultyId'] as String?;
    String selectedCourseType = course['courseType'] as String? ?? 'CORE';
    bool isActive = course['isActive'] as bool? ?? true;

    final formKey = GlobalKey<FormState>();
    final facultyList = _users.where((u) => u['role'] == 'FACULTY' && u['status'] == 'ACTIVE').toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_outlined, color: AppTheme.secondaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Edit Course Details'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: codeController,
                            decoration: const InputDecoration(
                              labelText: 'Course Code',
                              prefixIcon: Icon(Icons.tag),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Course Name',
                              prefixIcon: Icon(Icons.book_outlined),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Branch Dropdown
                    DropdownButtonFormField<String>(
                      value: selectedBranch,
                      decoration: const InputDecoration(
                        labelText: 'Branch / Department',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                      onChanged: (val) => setDialogState(() => selectedBranch = val),
                    ),
                    const SizedBox(height: 14),

                    // Year & Semester
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selectedYear,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                              prefixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                            items: [1, 2, 3, 4]
                                .map((y) => DropdownMenuItem(value: y, child: Text('Year $y')))
                                .toList(),
                            onChanged: (val) => setDialogState(() => selectedYear = val ?? 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selectedSemester,
                            decoration: const InputDecoration(
                              labelText: 'Semester',
                              prefixIcon: Icon(Icons.school_outlined),
                            ),
                            items: [1, 2, 3, 4, 5, 6, 7, 8]
                                .map((s) => DropdownMenuItem(value: s, child: Text('Sem $s')))
                                .toList(),
                            onChanged: (val) => setDialogState(() => selectedSemester = val ?? 1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Assigned Faculty
                    DropdownButtonFormField<String?>(
                      value: selectedFacultyId,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Faculty',
                        prefixIcon: Icon(Icons.person_pin_outlined),
                        helperText: 'Only the assigned faculty can conduct attendance',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Unassigned / None'),
                        ),
                        ...facultyList.map((f) => DropdownMenuItem<String?>(
                          value: f['id'] as String,
                          child: Text('${f['fullName']} (${f['email']})', overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: (val) => setDialogState(() => selectedFacultyId = val),
                    ),
                    const SizedBox(height: 14),

                    // Academic Session & Course Type
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: sessionController,
                            decoration: const InputDecoration(
                              labelText: 'Academic Session',
                              hintText: 'e.g. 2024-2025',
                              prefixIcon: Icon(Icons.access_time_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedCourseType,
                            decoration: const InputDecoration(
                              labelText: 'Course Type',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: ['CORE', 'ELECTIVE', 'LAB', 'SEMINAR']
                                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                .toList(),
                            onChanged: (val) => setDialogState(() => selectedCourseType = val ?? 'CORE'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Credits & Active Status
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: creditsController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Credits',
                              hintText: 'e.g. 4',
                              prefixIcon: Icon(Icons.stars_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active Course', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(isActive ? 'Can conduct sessions' : 'Sessions disabled', style: const TextStyle(fontSize: 11)),
                            value: isActive,
                            activeColor: AppTheme.successColor,
                            onChanged: (val) => setDialogState(() => isActive = val),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  await ref.read(apiClientProvider).updateCourse(
                    course['id'] as String,
                    code: codeController.text.trim().toUpperCase(),
                    name: nameController.text.trim(),
                    branch: selectedBranch,
                    year: selectedYear,
                    semester: selectedSemester,
                    facultyId: selectedFacultyId,
                    academicSession: sessionController.text.trim(),
                    courseType: selectedCourseType,
                    credits: int.tryParse(creditsController.text.trim()),
                    isActive: isActive,
                  );
                  _loadCourses();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Course updated successfully!'),
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
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete Course ──────────────────────────────────────────────────────────
  Future<void> _deleteCourse(Map<String, dynamic> course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 24),
            SizedBox(width: 10),
            Text('Delete Course'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${course['code']} — ${course['name']}"?\n\nAll student enrollments and session history for this course will be affected. This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Course'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(apiClientProvider).deleteCourse(course['id'] as String);
      _loadCourses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Course ${course['code']} deleted!'),
            backgroundColor: AppTheme.warningColor,
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
  }

  // ── Edit User Dialog ───────────────────────────────────────────────────────
  void _showEditUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['fullName'] as String? ?? '');
    final usernameController = TextEditingController(text: user['username'] as String? ?? '');
    final emailController = TextEditingController(text: user['email'] as String? ?? '');
    final fatherNameController = TextEditingController(text: user['fatherName'] as String? ?? '');
    final rollNoController = TextEditingController(text: user['rollNo'] as String? ?? '');

    String? selectedBranch = user['branch'] as String?;
    if (selectedBranch != null && !_branches.contains(selectedBranch)) {
      selectedBranch = null;
    }
    String? selectedSection = user['section'] as String?;
    int? selectedSemester = user['semester'] as int?;

    final role = user['role'] as String? ?? 'STUDENT';
    final isStudent = role == 'STUDENT';
    final isAdmin = role == 'ADMIN';

    const sections = ['A', 'B', 'C', 'D'];
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_outlined, color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text('Edit ${role.toLowerCase()} Profile'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.alternate_email),
                        helperText: 'Letters, numbers, underscores (3-30 chars)',
                      ),
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (!isAdmin && val.isEmpty) return 'Username is required';
                        if (val.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]{3,30}$').hasMatch(val)) {
                          return '3-30 characters (letters, numbers, underscores)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: !isAdmin ? 'College Email (@kiet.edu)' : 'Email Address',
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        final val = v?.trim().toLowerCase() ?? '';
                        if (val.isEmpty) return 'Email is required';
                        if (!val.contains('@')) return 'Enter a valid email';
                        if (!isAdmin && !val.endsWith('@kiet.edu')) {
                          return 'Email must end with @kiet.edu';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    if (!isAdmin) ...[
                      TextFormField(
                        controller: fatherNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: "Father's Name",
                          prefixIcon: Icon(Icons.family_restroom_outlined),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? "Father's name is required" : null,
                      ),
                      const SizedBox(height: 14),

                      DropdownButtonFormField<String>(
                        value: selectedBranch,
                        decoration: InputDecoration(
                          labelText: isStudent ? 'Branch' : 'Department / Branch',
                          prefixIcon: const Icon(Icons.account_tree_outlined),
                        ),
                        items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                        onChanged: (val) => setDialogState(() => selectedBranch = val),
                        validator: (v) => v == null ? 'Please select a branch' : null,
                      ),
                      const SizedBox(height: 14),
                    ],

                    if (isStudent) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: selectedSection,
                              decoration: const InputDecoration(
                                labelText: 'Section',
                                prefixIcon: Icon(Icons.group_outlined),
                              ),
                              items: sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: (val) => setDialogState(() => selectedSection = val),
                              validator: (v) => v == null ? 'Select' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: rollNoController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                labelText: 'Roll No',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              validator: (v) {
                                final val = v?.trim() ?? '';
                                if (val.isEmpty) return 'Required';
                                if (!RegExp(r'^[0-9]+$').hasMatch(val)) return 'Digits only';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      DropdownButtonFormField<int>(
                        value: selectedSemester,
                        decoration: const InputDecoration(
                          labelText: 'Semester',
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        items: [1, 2, 3, 4, 5, 6, 7, 8]
                            .map((s) => DropdownMenuItem(value: s, child: Text('Semester $s')))
                            .toList(),
                        onChanged: (val) => setDialogState(() => selectedSemester = val),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  await ref.read(apiClientProvider).updateUser(
                    user['id'] as String,
                    fullName: nameController.text.trim(),
                    username: usernameController.text.trim().isNotEmpty ? usernameController.text.trim().toLowerCase() : null,
                    email: emailController.text.trim().toLowerCase(),
                    fatherName: fatherNameController.text.trim().isNotEmpty ? fatherNameController.text.trim() : null,
                    branch: selectedBranch,
                    section: selectedSection,
                    rollNo: rollNoController.text.trim().isNotEmpty ? rollNoController.text.trim() : null,
                    semester: selectedSemester,
                  );
                  _loadUsers();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User profile updated!'),
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
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Toggle User Status (Activate / Deactivate) ──────────────────────────────
  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final currentStatus = user['status'] as String? ?? 'ACTIVE';
    final newStatus = currentStatus == 'ACTIVE' ? 'DEACTIVATED' : 'ACTIVE';

    if (newStatus == 'DEACTIVATED') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.block_outlined, color: AppTheme.warningColor, size: 24),
              SizedBox(width: 10),
              Text('Deactivate User'),
            ],
          ),
          content: Text(
            'Deactivate account for "${user['fullName']}" (${user['email']})?\n\nThis user will be immediately blocked from logging in or conducting attendance sessions.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warningColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      await ref.read(apiClientProvider).setUserStatus(user['id'] as String, newStatus);
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${user['fullName']} is now $newStatus'),
            backgroundColor: newStatus == 'ACTIVE' ? AppTheme.successColor : AppTheme.warningColor,
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
  }

  // ── Confirm Delete User ────────────────────────────────────────────────────
  Future<void> _confirmDeleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: AppTheme.errorColor, size: 24),
            SizedBox(width: 10),
            Text('Permanently Delete User'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${user['fullName']}" (${user['email']})?\n\nAll face biometric data, device registrations, and enrollments will be permanently removed. This action CANNOT be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(apiClientProvider).deleteUser(user['id'] as String);
      await Future.wait([_loadUsers(), _loadPendingUsers()]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['fullName']} deleted successfully.'),
            backgroundColor: AppTheme.warningColor,
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
  }

  // ── Create User / Admin Dialog ─────────────────────────────────────────────
  void _showCreateUserDialog() {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final fatherNameController = TextEditingController();
    final rollNoController = TextEditingController();
    final passwordController = TextEditingController();

    String selectedRole = 'STUDENT';
    String? selectedBranch;
    String? selectedSection;
    final formKey = GlobalKey<FormState>();

    const branches = [
      'CSE',
      'CS',
      'CSE-AI',
      'CSE-AIML',
      'IT',
      'ECE',
      'EN',
      'ME',
      'CE',
      'MCA',
      'MTech',
    ];

    const sections = ['A', 'B', 'C', 'D'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isStudent = selectedRole == 'STUDENT';
          final isAdmin = selectedRole == 'ADMIN';

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person_add, color: AppTheme.primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Add User / Admin'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Role Selection Chips
                      Text(
                        'Account Role',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['STUDENT', 'FACULTY', 'ADMIN'].map((role) {
                          final isSelected = selectedRole == role;
                          final roleColor = switch (role) {
                            'ADMIN' => AppTheme.warningColor,
                            'FACULTY' => AppTheme.secondaryColor,
                            _ => AppTheme.primaryColor,
                          };
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                role,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : roleColor,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: roleColor,
                              onSelected: (_) => setDialogState(() => selectedRole = role),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Full Name
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          hintText: 'e.g. John Doe',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 14),

                      // Username
                      TextFormField(
                        controller: usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'e.g. johndoe',
                          prefixIcon: Icon(Icons.alternate_email),
                          helperText: 'Letters, numbers, underscores (3-30 chars)',
                        ),
                        validator: (v) {
                          final val = v?.trim() ?? '';
                          if (!isAdmin && val.isEmpty) return 'Username is required';
                          if (val.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]{3,30}$').hasMatch(val)) {
                            return '3-30 characters (letters, numbers, underscores)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Email Address
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: !isAdmin ? 'College Email (@kiet.edu)' : 'Email Address',
                          hintText: !isAdmin ? 'name@kiet.edu' : 'admin@example.com',
                          prefixIcon: const Icon(Icons.email_outlined),
                          helperText: !isAdmin ? 'Must end with @kiet.edu' : null,
                        ),
                        validator: (v) {
                          final val = v?.trim().toLowerCase() ?? '';
                          if (val.isEmpty) return 'Email is required';
                          if (!val.contains('@')) return 'Enter a valid email';
                          if (!isAdmin && !val.endsWith('@kiet.edu')) {
                            return 'Email must end with @kiet.edu';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Father's Name (for Student & Faculty)
                      if (!isAdmin) ...[
                        TextFormField(
                          controller: fatherNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: "Father's Name",
                            hintText: "Enter father's name",
                            prefixIcon: Icon(Icons.family_restroom_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? "Father's name is required" : null,
                        ),
                        const SizedBox(height: 14),

                        // Branch Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: selectedBranch,
                          decoration: InputDecoration(
                            labelText: isStudent ? 'Branch' : 'Department / Branch',
                            prefixIcon: const Icon(Icons.account_tree_outlined),
                          ),
                          items: branches
                              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                              .toList(),
                          onChanged: (val) => setDialogState(() => selectedBranch = val),
                          validator: (v) => v == null ? 'Please select a branch' : null,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Student-specific: Section & Roll Number
                      if (isStudent) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedSection,
                                decoration: const InputDecoration(
                                  labelText: 'Section',
                                  prefixIcon: Icon(Icons.group_outlined),
                                ),
                                items: sections
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                    .toList(),
                                onChanged: (val) => setDialogState(() => selectedSection = val),
                                validator: (v) => v == null ? 'Select' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: rollNoController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Roll No',
                                  hintText: 'e.g. 2100290100001',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: (v) {
                                  final val = v?.trim() ?? '';
                                  if (val.isEmpty) return 'Required';
                                  if (!RegExp(r'^\d+$').hasMatch(val)) return 'Digits only';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Password
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          hintText: 'Minimum 8 characters',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Password is required';
                          if (v.length < 8) return 'At least 8 characters';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(ctx);
                  try {
                    await ref.read(apiClientProvider).createUser(
                      email: emailController.text.trim().toLowerCase(),
                      username: usernameController.text.trim().isNotEmpty
                          ? usernameController.text.trim().toLowerCase()
                          : null,
                      password: passwordController.text,
                      fullName: nameController.text.trim(),
                      role: selectedRole,
                      branch: !isAdmin ? selectedBranch : null,
                      section: isStudent ? selectedSection : null,
                      rollNo: isStudent ? rollNoController.text.trim() : null,
                      fatherName: !isAdmin ? fatherNameController.text.trim() : null,
                    );
                    _loadUsers();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('New $selectedRole created successfully!'),
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
                child: const Text('Create User'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Enroll Students Dialog ─────────────────────────────────────────────────
  void _showEnrollDialog(Map<String, dynamic> course) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CourseEnrollmentDialog(
        course: course,
        allUsers: _users,
        onEnrollmentChanged: _loadCourses,
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
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.people_outline),
                  if (_pendingUsers.isNotEmpty)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppTheme.warningColor,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${_pendingUsers.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              text: _pendingUsers.isNotEmpty
                  ? 'Users (${_pendingUsers.length} pending)'
                  : 'Users (${_users.length})',
            ),
          ],
        ),
      ),

      // FAB changes label based on tab
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _currentTab == 0 ? _showCreateCourseDialog : _showCreateUserDialog,
        backgroundColor: _currentTab == 0 ? AppTheme.primaryColor : AppTheme.warningColor,
        icon: Icon(_currentTab == 0 ? Icons.add : Icons.person_add, color: Colors.white),
        label: Text(
          _currentTab == 0 ? 'New Course' : 'New User / Admin',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                if (_pendingUsers.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _StatChip(
                    icon: Icons.pending_actions,
                    label: 'Pending',
                    value: '${_pendingUsers.length}',
                    color: AppTheme.warningColor,
                  ),
                ],
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

    final query = _courseSearch.toLowerCase();
    final filteredCourses = _courses.where((c) {
      final code = (c['code'] as String? ?? '').toLowerCase();
      final name = (c['name'] as String? ?? '').toLowerCase();
      final branch = c['branch'] as String?;
      final matchesSearch = query.isEmpty || code.contains(query) || name.contains(query);
      final matchesBranch = _courseBranchFilter == null || branch == _courseBranchFilter;
      return matchesSearch && matchesBranch;
    }).toList();

    return Column(
      children: [
        // ── Search and Filter Bar ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by course code or name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _courseSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _courseSearch = ''),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _courseSearch = val.trim()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String?>(
                  value: _courseBranchFilter,
                  decoration: const InputDecoration(
                    labelText: 'Branch',
                    prefixIcon: Icon(Icons.filter_list, size: 18),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Branches'),
                    ),
                    ..._branches.map((b) => DropdownMenuItem<String?>(
                      value: b,
                      child: Text(b),
                    )),
                  ],
                  onChanged: (val) => setState(() => _courseBranchFilter = val),
                ),
              ),
            ],
          ),
        ),

        // ── Course List ────────────────────────────────────────────────────
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCourses,
            child: filteredCourses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.book_outlined, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          _courses.isEmpty ? 'No courses yet' : 'No courses matching filter',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _courses.isEmpty
                              ? 'Tap "+ New Course" to create a course'
                              : 'Try changing your search or branch filter',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredCourses.length,
                    itemBuilder: (context, index) {
                      final course = filteredCourses[index];
                      return _CourseCard(
                        course: course,
                        onEnroll: () => _showEnrollDialog(course),
                        onEdit: () => _showEditCourseDialog(course),
                        onDelete: () => _deleteCourse(course),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  // ── Users Tab ──────────────────────────────────────────────────────────────
  Widget _buildUsersTab() {
    if (_isLoadingUsers || _isLoadingPending) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentUserId = ref.watch(authStateProvider).userId;
    final currentUserEmail = ref.watch(authStateProvider).email;

    final q = _userSearchQuery.toLowerCase();
    final filteredUsers = _users.where((u) {
      final name = (u['fullName'] as String? ?? '').toLowerCase();
      final email = (u['email'] as String? ?? '').toLowerCase();
      final username = (u['username'] as String? ?? '').toLowerCase();
      final rollNo = (u['rollNo'] as String? ?? '').toLowerCase();
      final branch = u['branch'] as String?;
      final role = u['role'] as String? ?? '';
      final status = u['status'] as String? ?? 'ACTIVE';

      final matchesQuery = q.isEmpty ||
          name.contains(q) ||
          email.contains(q) ||
          username.contains(q) ||
          rollNo.contains(q);
      final matchesRole = _userRoleFilter == 'ALL' || role == _userRoleFilter;
      final matchesStatus = _userStatusFilter == 'ALL' || status == _userStatusFilter;
      final matchesBranch = _userBranchFilter == null || branch == _userBranchFilter;

      return matchesQuery && matchesRole && matchesStatus && matchesBranch;
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => Future.wait([_loadUsers(), _loadPendingUsers()]),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Search and Filter Bar ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _userSearchController,
                        decoration: InputDecoration(
                          hintText: 'Search name, email, username, roll...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _userSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _userSearchController.clear();
                                    setState(() => _userSearchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        onChanged: (val) => setState(() => _userSearchQuery = val.trim()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String?>(
                        value: _userBranchFilter,
                        decoration: const InputDecoration(
                          labelText: 'Branch',
                          prefixIcon: Icon(Icons.account_tree_outlined, size: 18),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Branches'),
                          ),
                          ..._branches.map((b) => DropdownMenuItem<String?>(
                            value: b,
                            child: Text(b),
                          )),
                        ],
                        onChanged: (val) => setState(() => _userBranchFilter = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Role and Status filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Role: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      for (final r in ['ALL', 'STUDENT', 'FACULTY', 'ADMIN']) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(r == 'ALL' ? 'All' : r, style: const TextStyle(fontSize: 11)),
                            selected: _userRoleFilter == r,
                            onSelected: (_) => setState(() => _userRoleFilter = r),
                          ),
                        ),
                      ],
                      const SizedBox(width: 14),
                      const Text('Status: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      for (final s in ['ALL', 'ACTIVE', 'DEACTIVATED']) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(s == 'ALL' ? 'All' : s, style: const TextStyle(fontSize: 11)),
                            selected: _userStatusFilter == s,
                            onSelected: (_) => setState(() => _userStatusFilter = s),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Pending Approvals Banner ─────────────────────────────────────
          if (_pendingUsers.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.14),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pending_actions, color: AppTheme.warningColor, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Pending Approvals (${_pendingUsers.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.warningColor,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Review new registrations',
                          style: TextStyle(fontSize: 11, color: AppTheme.warningColor.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  ..._pendingUsers.map((user) => _PendingUserTile(
                    user: user,
                    onApprove: () => _approveUser(user),
                    onReject: () => _rejectUser(user),
                  )),
                ],
              ),
            ),

          // ── Filtered Users List ──────────────────────────────────────────
          if (filteredUsers.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No users match your criteria', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('Try adjusting search query or filters', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(
                'Showing ${filteredUsers.length} user${filteredUsers.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
            ),
            ...filteredUsers.map((user) {
              final isSelf = (user['id'] == currentUserId) || (user['email'] == currentUserEmail);
              return _UserCard(
                user: user,
                isSelf: isSelf,
                onEdit: () => _showEditUserDialog(user),
                onToggleStatus: () => _toggleUserStatus(user),
                onDelete: () => _confirmDeleteUser(user),
              );
            }),
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

// ─── Course Card ──────────────────────────────────────────────────────────────
class _CourseCard extends StatelessWidget {
  final Map<String, dynamic> course;
  final VoidCallback onEnroll;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CourseCard({
    required this.course,
    required this.onEnroll,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final code = course['code'] as String? ?? '';
    final name = course['name'] as String? ?? '';
    final branch = course['branch'] as String?;
    final year = course['year'] as int?;
    final semester = course['semester'] as int?;
    final facultyName = course['facultyName'] as String?;
    final academicSession = course['academicSession'] as String?;
    final courseType = course['courseType'] as String? ?? 'CORE';
    final credits = course['credits'] as int?;
    final isActive = course['isActive'] as bool? ?? true;
    final enrolledCount = (course['enrolledCount'] as num?)?.toInt() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? Colors.transparent : AppTheme.errorColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Code, Status, and Actions
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryColor, Color(0xFF8B7CF7)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Course Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    courseType,
                    style: const TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Status Badge (Active / Inactive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isActive ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (isActive ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? AppTheme.successColor : AppTheme.errorColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          color: isActive ? AppTheme.successColor : AppTheme.errorColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Actions Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'enroll') onEnroll();
                    if (val == 'edit') onEdit();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'enroll',
                      child: Row(
                        children: [
                          Icon(Icons.person_add_outlined, size: 18, color: AppTheme.primaryColor),
                          SizedBox(width: 10),
                          Text('Enroll Students'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18, color: AppTheme.secondaryColor),
                          SizedBox(width: 10),
                          Text('Edit Course'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                          SizedBox(width: 10),
                          Text('Delete Course', style: TextStyle(color: AppTheme.errorColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Course Name
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 10),

            // Metadata Chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metaChip(Icons.people_outline, '$enrolledCount Enrolled', AppTheme.primaryColor),
                if (branch != null && branch.isNotEmpty)
                  _metaChip(Icons.account_tree_outlined, 'Branch: $branch', Colors.teal),
                if (year != null || semester != null)
                  _metaChip(
                    Icons.school_outlined,
                    '${year != null ? 'Yr $year • ' : ''}${semester != null ? 'Sem $semester' : ''}',
                    Colors.indigo,
                  ),
                if (credits != null)
                  _metaChip(Icons.stars_outlined, '$credits Credits', Colors.amber.shade700),
                if (academicSession != null && academicSession.isNotEmpty)
                  _metaChip(Icons.access_time_outlined, 'Session: $academicSession', Colors.purple),
                if (facultyName != null && facultyName.isNotEmpty)
                  _metaChip(Icons.person_pin_outlined, 'Faculty: $facultyName', AppTheme.secondaryColor)
                else
                  _metaChip(Icons.person_off_outlined, 'No Faculty Assigned', AppTheme.warningColor),
              ],
            ),
            const SizedBox(height: 12),

            // Quick Actions Footer
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onEnroll,
                  icon: const Icon(Icons.people_outline, size: 16),
                  label: Text('Enrolled Students ($enrolledCount)', style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.secondaryColor),
                  tooltip: 'Edit Course Details',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                  tooltip: 'Delete Course',
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── User Card ────────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isSelf;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.isSelf,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = user['fullName'] as String? ?? '';
    final username = user['username'] as String? ?? '';
    final email = user['email'] as String? ?? '';
    final role = user['role'] as String? ?? 'STUDENT';
    final status = user['status'] as String? ?? 'ACTIVE';
    final branch = user['branch'] as String?;
    final section = user['section'] as String?;
    final rollNo = user['rollNo'] as String?;
    final fatherName = user['fatherName'] as String?;
    final semester = user['semester'] as int?;

    final isActive = status == 'ACTIVE';
    final isDeactivated = status == 'DEACTIVATED';

    Color roleColor;
    if (role == 'ADMIN') {
      roleColor = AppTheme.warningColor;
    } else if (role == 'FACULTY') {
      roleColor = AppTheme.secondaryColor;
    } else {
      roleColor = AppTheme.primaryColor;
    }

    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDeactivated ? AppTheme.errorColor.withValues(alpha: 0.3) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: roleColor.withValues(alpha: 0.15),
                  child: Text(
                    initials,
                    style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (username.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '@$username',
                              style: TextStyle(
                                fontSize: 11,
                                color: roleColor.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (isSelf) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('YOU', style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(email, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),

                // Role Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    role.toLowerCase(),
                    style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isActive ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (isActive ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    status.toLowerCase(),
                    style: TextStyle(
                      color: isActive ? AppTheme.successColor : AppTheme.errorColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Metadata Chips
            if (fatherName != null || branch != null || section != null || rollNo != null || semester != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (fatherName != null && fatherName.isNotEmpty)
                    _metaBadge(Icons.family_restroom, 'Father: $fatherName'),
                  if (branch != null && branch.isNotEmpty)
                    _metaBadge(Icons.account_tree_outlined, 'Branch: $branch'),
                  if (section != null && section.isNotEmpty)
                    _metaBadge(Icons.group_outlined, 'Sec: $section'),
                  if (rollNo != null && rollNo.isNotEmpty)
                    _metaBadge(Icons.badge_outlined, 'Roll: $rollNo'),
                  if (semester != null)
                    _metaBadge(Icons.school_outlined, 'Sem: $semester'),
                ],
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action Buttons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Edit Profile
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppTheme.secondaryColor,
                  ),
                ),
                const SizedBox(width: 6),

                // Toggle Deactivate / Activate
                if (!isSelf) ...[
                  TextButton.icon(
                    onPressed: onToggleStatus,
                    icon: Icon(
                      isActive ? Icons.block_outlined : Icons.check_circle_outline,
                      size: 15,
                    ),
                    label: Text(
                      isActive ? 'Deactivate' : 'Activate',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isActive ? AppTheme.warningColor : AppTheme.successColor,
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Permanently Delete
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_forever_outlined, size: 15),
                    label: const Text('Delete', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppTheme.errorColor,
                    ),
                  ),
                ] else ...[
                  const Tooltip(
                    message: 'You cannot deactivate or delete your own account',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('(Current User)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ─── Pending User Tile ────────────────────────────────────────────────────────
class _PendingUserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingUserTile({
    required this.user,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final name = user['fullName'] as String? ?? '';
    final username = user['username'] as String? ?? '';
    final email = user['email'] as String? ?? '';
    final role = (user['role'] as String? ?? '').toLowerCase();
    final branch = user['branch'] as String?;
    final section = user['section'] as String?;
    final rollNo = user['rollNo'] as String?;
    final fatherName = user['fatherName'] as String?;

    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();
    final roleColor = role == 'faculty' ? AppTheme.secondaryColor : AppTheme.primaryColor;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.warningColor.withValues(alpha: 0.15),
                child: Text(
                  initials,
                  style: const TextStyle(color: AppTheme.warningColor, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 8),
                        if (username.isNotEmpty) ...[
                          Text(
                            '@$username',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryColor.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(fontSize: 11, color: roleColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Approve button
              Tooltip(
                message: 'Approve Registration',
                child: InkWell(
                  onTap: onApprove,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: AppTheme.successColor, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Reject button
              Tooltip(
                message: 'Reject Registration',
                child: InkWell(
                  onTap: onReject,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.cancel_outlined, color: AppTheme.errorColor, size: 24),
                  ),
                ),
              ),
            ],
          ),

          // Chips / metadata row
          if (branch != null || section != null || rollNo != null || fatherName != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (fatherName != null && fatherName.isNotEmpty)
                  _infoChip(Icons.family_restroom, 'Father: $fatherName', Colors.blueGrey),
                if (branch != null && branch.isNotEmpty)
                  _infoChip(Icons.account_tree_outlined, 'Branch: $branch', Colors.teal),
                if (section != null && section.isNotEmpty)
                  _infoChip(Icons.group_outlined, 'Section: $section', Colors.indigo),
                if (rollNo != null && rollNo.isNotEmpty)
                  _infoChip(Icons.badge_outlined, 'Roll No: $rollNo', Colors.amber),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Comprehensive Course Enrollment & Enrolled Students Dialog ───────────────
class _CourseEnrollmentDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> course;
  final List<Map<String, dynamic>> allUsers;
  final VoidCallback onEnrollmentChanged;

  const _CourseEnrollmentDialog({
    required this.course,
    required this.allUsers,
    required this.onEnrollmentChanged,
  });

  @override
  ConsumerState<_CourseEnrollmentDialog> createState() => _CourseEnrollmentDialogState();
}

class _CourseEnrollmentDialogState extends ConsumerState<_CourseEnrollmentDialog>
    with SingleTickerProviderStateMixin {
  late TabController _dialogTabController;
  List<Map<String, dynamic>> _enrolledStudents = [];
  bool _isLoadingEnrolled = true;
  String? _errorMessage;

  final Set<String> _selectedStudentIds = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _dialogTabController = TabController(length: 2, vsync: this);
    _loadEnrolledStudents();
  }

  @override
  void dispose() {
    _dialogTabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEnrolledStudents() async {
    setState(() {
      _isLoadingEnrolled = true;
      _errorMessage = null;
    });
    try {
      final list = await ref
          .read(apiClientProvider)
          .listCourseStudents(widget.course['id'] as String);
      if (mounted) {
        setState(() {
          _enrolledStudents = list;
          _isLoadingEnrolled = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoadingEnrolled = false;
        });
      }
    }
  }

  Future<void> _unenrollStudent(Map<String, dynamic> student) async {
    final name = student['fullName'] as String? ?? 'this student';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_remove_outlined, color: AppTheme.errorColor, size: 24),
            SizedBox(width: 10),
            Text('Remove Student'),
          ],
        ),
        content: Text(
          'Remove "$name" from "${widget.course['code']} — ${widget.course['name']}"?\n\nThis student will no longer be eligible to mark attendance for this course.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove Student'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(apiClientProvider).unenrollStudent(
        widget.course['id'] as String,
        student['id'] as String,
      );
      setState(() {
        _enrolledStudents.removeWhere((s) => s['id'] == student['id']);
      });
      widget.onEnrollmentChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name removed from course.'),
            backgroundColor: AppTheme.warningColor,
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
  }

  Future<void> _enrollSelectedStudents() async {
    if (_selectedStudentIds.isEmpty) return;
    try {
      final res = await ref.read(apiClientProvider).enrollStudents(
        widget.course['id'] as String,
        _selectedStudentIds.toList(),
      );
      final enrolled = res['enrolled'] ?? _selectedStudentIds.length;
      setState(() {
        _selectedStudentIds.clear();
      });
      await _loadEnrolledStudents();
      widget.onEnrollmentChanged();
      _dialogTabController.animateTo(0); // Switch to enrolled tab

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$enrolled student(s) successfully enrolled!'),
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
  }

  Future<void> _showBulkEnrollBranchConfirmation() async {
    final branch = widget.course['branch'] as String?;
    if (branch == null || branch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Course has no branch assigned. Edit the course to assign a branch first.'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    try {
      final preview = await ref
          .read(apiClientProvider)
          .getBulkEnrollPreview(widget.course['id'] as String);

      final total = preview['totalBranchStudents'] ?? 0;
      final already = preview['alreadyEnrolledCount'] ?? 0;
      final newCount = preview['newToEnrollCount'] ?? 0;

      if (!mounted) return;

      if (newCount == 0) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppTheme.successColor, size: 24),
                SizedBox(width: 10),
                Text('All Students Enrolled'),
              ],
            ),
            content: Text(
              'All $total active students from branch "$branch" are already enrolled in this course.',
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.group_add_outlined, color: AppTheme.primaryColor, size: 24),
              const SizedBox(width: 10),
              Text('Bulk Enroll $branch Students'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enroll all active students from branch "$branch" into "${widget.course['code']} — ${widget.course['name']}"?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _previewRow('Total Active in $branch', '$total'),
                    const Divider(height: 12),
                    _previewRow('Already Enrolled', '$already'),
                    const Divider(height: 12),
                    _previewRow('New to be Enrolled', '$newCount', isHighlight: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Existing enrollments will not be duplicated. You can still remove individual students later.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Enroll $newCount Students'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      final res = await ref
          .read(apiClientProvider)
          .bulkEnrollBranch(widget.course['id'] as String);

      final enrolled = res['enrolledCount'] ?? 0;
      await _loadEnrolledStudents();
      widget.onEnrollmentChanged();
      _dialogTabController.animateTo(0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$enrolled students from branch "$branch" enrolled successfully!'),
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
  }

  Widget _previewRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: isHighlight ? AppTheme.primaryColor : null)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isHighlight ? AppTheme.primaryColor : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final courseCode = widget.course['code'] as String? ?? '';
    final courseName = widget.course['name'] as String? ?? '';
    final branch = widget.course['branch'] as String?;
    final enrolledIds = _enrolledStudents.map((s) => s['id'] as String).toSet();

    // All active student users
    final allStudents = widget.allUsers
        .where((u) => u['role'] == 'STUDENT' && u['status'] == 'ACTIVE')
        .toList();

    final q = _searchQuery.toLowerCase();
    final filteredAvailableStudents = allStudents.where((s) {
      final name = (s['fullName'] as String? ?? '').toLowerCase();
      final email = (s['email'] as String? ?? '').toLowerCase();
      final roll = (s['rollNo'] as String? ?? '').toLowerCase();
      final sBranch = (s['branch'] as String? ?? '').toLowerCase();
      return q.isEmpty ||
          name.contains(q) ||
          email.contains(q) ||
          roll.contains(q) ||
          sBranch.contains(q);
    }).toList();

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.school_outlined, color: AppTheme.primaryColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$courseCode — $courseName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${branch != null ? 'Branch: $branch • ' : ''}Course Enrollment Management',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bulk Enroll from Branch Button (if branch assigned)
          if (branch != null && branch.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showBulkEnrollBranchConfirmation,
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text('Enroll All Students from Branch ($branch)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                  foregroundColor: AppTheme.primaryColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Tabs
          TabBar(
            controller: _dialogTabController,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.primaryColor,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.how_to_reg_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Enrolled (${_enrolledStudents.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add_outlined, size: 16),
                    const SizedBox(width: 6),
                    const Text('Enroll New'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: 420,
        child: TabBarView(
          controller: _dialogTabController,
          children: [
            // ── Tab 1: Enrolled Students ──────────────────────────────────
            _buildEnrolledTab(),

            // ── Tab 2: Enroll New Students ────────────────────────────────
            _buildEnrollNewTab(filteredAvailableStudents, enrolledIds),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildEnrolledTab() {
    if (_isLoadingEnrolled) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 36),
            const SizedBox(height: 8),
            Text('Failed to load: $_errorMessage', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadEnrolledStudents, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_enrolledStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No students enrolled yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Switch to the "Enroll New" tab or use "Enroll All from Branch"',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _enrolledStudents.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final student = _enrolledStudents[i];
        final name = student['fullName'] as String? ?? '';
        final email = student['email'] as String? ?? '';
        final rollNo = student['rollNo'] as String?;
        final sBranch = student['branch'] as String?;
        final section = student['section'] as String?;

        final initials = name.trim().isEmpty
            ? '?'
            : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
            child: Text(
              initials,
              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 2),
              Wrap(
                spacing: 6,
                children: [
                  if (rollNo != null && rollNo.isNotEmpty)
                    Text('Roll: $rollNo', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (sBranch != null && sBranch.isNotEmpty)
                    Text('• $sBranch', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (section != null && section.isNotEmpty)
                    Text('• Sec $section', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
          ),
          trailing: Tooltip(
            message: 'Remove student from course',
            child: IconButton(
              icon: const Icon(Icons.person_remove_outlined, color: AppTheme.errorColor, size: 20),
              onPressed: () => _unenrollStudent(student),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnrollNewTab(List<Map<String, dynamic>> students, Set<String> enrolledIds) {
    final unenrolledStudents = students.where((s) => !enrolledIds.contains(s['id'])).toList();

    return Column(
      children: [
        const SizedBox(height: 8),
        // Search Input
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name, email, roll number...',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
          ),
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
        ),
        const SizedBox(height: 8),

        // Quick Selection Bar
        Row(
          children: [
            Text(
              '${_selectedStudentIds.length} selected',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (unenrolledStudents.isNotEmpty) ...[
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedStudentIds.addAll(unenrolledStudents.map((s) => s['id'] as String));
                  });
                },
                child: const Text('Select All Available', style: TextStyle(fontSize: 12)),
              ),
              if (_selectedStudentIds.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selectedStudentIds.clear()),
                  child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ],
        ),
        const Divider(height: 1),

        // Student List
        Expanded(
          child: students.isEmpty
              ? const Center(
                  child: Text('No students match the search filter.', style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final s = students[i];
                    final id = s['id'] as String;
                    final isEnrolled = enrolledIds.contains(id);
                    final name = s['fullName'] as String? ?? '';
                    final email = s['email'] as String? ?? '';
                    final rollNo = s['rollNo'] as String?;
                    final sBranch = s['branch'] as String?;
                    final section = s['section'] as String?;

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isEnrolled ? Colors.grey : null,
                        ),
                      ),
                      subtitle: Text(
                        '$email${rollNo != null ? ' • Roll: $rollNo' : ''}${sBranch != null ? ' • $sBranch' : ''}${section != null ? ' (Sec $section)' : ''}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      trailing: isEnrolled
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: 12, color: AppTheme.successColor),
                                  SizedBox(width: 4),
                                  Text(
                                    'Enrolled',
                                    style: TextStyle(
                                      color: AppTheme.successColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Checkbox(
                              value: _selectedStudentIds.contains(id),
                              activeColor: AppTheme.primaryColor,
                              onChanged: (v) {
                                setState(() {
                                  v == true ? _selectedStudentIds.add(id) : _selectedStudentIds.remove(id);
                                });
                              },
                            ),
                    );
                  },
                ),
        ),

        // Bottom Enroll Button
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedStudentIds.isEmpty ? null : _enrollSelectedStudents,
            child: Text('Enroll Selected (${_selectedStudentIds.length})'),
          ),
        ),
      ],
    );
  }
}
