import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _rollNoController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedRole = 'STUDENT';
  String? _selectedBranch;
  String? _selectedSection;
  bool _obscurePassword = true;

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

  static const List<String> _sections = ['A', 'B', 'C', 'D'];

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _fatherNameController.dispose();
    _rollNoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final isStudent = _selectedRole == 'STUDENT';

    final success = await ref.read(authStateProvider.notifier).register(
      email: _emailController.text.trim().toLowerCase(),
      username: _usernameController.text.trim().toLowerCase(),
      password: _passwordController.text,
      fullName: _nameController.text.trim(),
      role: _selectedRole,
      branch: _selectedBranch,
      section: isStudent ? _selectedSection : null,
      rollNo: isStudent ? _rollNoController.text.trim() : null,
      fatherName: _fatherNameController.text.trim(),
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration submitted! Your account is awaiting admin approval.'),
          backgroundColor: AppTheme.successColor,
          duration: Duration(seconds: 5),
        ),
      );
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isStudent = _selectedRole == 'STUDENT';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Create Account',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Join SecureAttend',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Role selector at top
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).inputDecorationTheme.fillColor ?? Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _RoleChip(
                              label: 'Student',
                              icon: Icons.school,
                              selected: _selectedRole == 'STUDENT',
                              onTap: () => setState(() => _selectedRole = 'STUDENT'),
                            ),
                          ),
                          Expanded(
                            child: _RoleChip(
                              label: 'Faculty',
                              icon: Icons.person,
                              selected: _selectedRole == 'FACULTY',
                              onTap: () => setState(() => _selectedRole = 'FACULTY'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (authState.error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          authState.error!,
                          style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Full Name
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => v?.trim().isEmpty == true ? 'Full name is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Username
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'Choose a unique username for login',
                        prefixIcon: Icon(Icons.alternate_email),
                        helperText: 'Letters, numbers, and underscores (3-30 chars)',
                      ),
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Username is required';
                        if (!RegExp(r'^[a-zA-Z0-9_]{3,30}$').hasMatch(val)) {
                          return 'Must be 3-30 chars (letters, numbers, underscores only)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // College Email
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: isStudent ? 'Student Email (@kiet.edu)' : 'Faculty Email (@kiet.edu)',
                        hintText: 'name@kiet.edu',
                        prefixIcon: const Icon(Icons.email_outlined),
                        helperText: 'Must end with @kiet.edu',
                      ),
                      validator: (v) {
                        final val = v?.trim().toLowerCase() ?? '';
                        if (val.isEmpty) return 'Email is required';
                        if (!val.endsWith('@kiet.edu')) {
                          return 'Email must end with @kiet.edu';
                        }
                        if (!val.contains('@') || val.indexOf('@') == 0) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Father's Name
                    TextFormField(
                      controller: _fatherNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Father's Name",
                        hintText: "Enter father's name",
                        prefixIcon: Icon(Icons.family_restroom_outlined),
                      ),
                      validator: (v) => v?.trim().isEmpty == true ? "Father's name is required" : null,
                    ),
                    const SizedBox(height: 16),

                    // Branch Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedBranch,
                      decoration: InputDecoration(
                        labelText: isStudent ? 'Branch' : 'Department / Branch',
                        prefixIcon: const Icon(Icons.account_tree_outlined),
                      ),
                      items: _branches
                          .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedBranch = val),
                      validator: (v) => v == null ? 'Please select your branch' : null,
                    ),
                    const SizedBox(height: 16),

                    // Student-specific fields: Section & Roll Number
                    if (isStudent) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: _selectedSection,
                              decoration: const InputDecoration(
                                labelText: 'Section',
                                prefixIcon: Icon(Icons.group_outlined),
                              ),
                              items: _sections
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) => setState(() => _selectedSection = val),
                              validator: (v) => v == null ? 'Select section' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Roll Number
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _rollNoController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                labelText: 'University Roll No',
                                hintText: 'e.g. 2100290100001',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              validator: (v) {
                                final val = v?.trim() ?? '';
                                if (val.isEmpty) return 'Roll number is required';
                                if (!RegExp(r'^\d+$').hasMatch(val)) {
                                  return 'Roll number must be numerical only';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Min 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 8) return 'At least 8 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: authState.isLoading ? null : _handleRegister,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: authState.isLoading
                            ? const SizedBox(
                                height: 24, width: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
