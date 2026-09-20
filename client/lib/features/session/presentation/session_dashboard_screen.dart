import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class SessionDashboardScreen extends ConsumerStatefulWidget {
  const SessionDashboardScreen({super.key});

  @override
  ConsumerState<SessionDashboardScreen> createState() => _SessionDashboardScreenState();
}

class _SessionDashboardScreenState extends ConsumerState<SessionDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSessions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
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

  List<Map<String, dynamic>> get _activeSessions =>
      _sessions.where((s) => s['status'] == 'ACTIVE').toList();
  List<Map<String, dynamic>> get _closedSessions =>
      _sessions.where((s) => s['status'] == 'CLOSED').toList();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final activeCount = _activeSessions.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sessions'),
            Text(
              authState.fullName ?? '',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          // Live dot if any active session
          if (activeCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.successColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$activeCount live',
                        style: const TextStyle(color: AppTheme.successColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Active (${_activeSessions.length})'),
            Tab(text: 'Closed (${_closedSessions.length})'),
          ],
        ),
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
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSessionList(_activeSessions, isActive: true),
                _buildSessionList(_closedSessions, isActive: false),
              ],
            ),
    );
  }

  Widget _buildSessionList(List<Map<String, dynamic>> sessions, {required bool isActive}) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? Icons.play_circle_outline : Icons.history,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? 'No active sessions' : 'No closed sessions',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              isActive ? 'Tap + to start a new session' : 'Closed sessions will appear here',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: sessions.length,
        itemBuilder: (context, index) => _SessionCard(
          session: sessions[index],
          isActive: isActive,
          onDisplayTap: () => context.go('/faculty/display/${sessions[index]['id']}'),
          onReviewTap: () => context.go('/faculty/review'),
          onRosterTap: () => _showAttendanceRoster(context, sessions[index]),
        ),
      ),
    );
  }

  void _showAttendanceRoster(BuildContext context, Map<String, dynamic> session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AttendanceRosterModal(session: session),
    );
  }
}

// ─── Session Card ─────────────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool isActive;
  final VoidCallback onDisplayTap;
  final VoidCallback onReviewTap;
  final VoidCallback onRosterTap;

  const _SessionCard({
    required this.session,
    required this.isActive,
    required this.onDisplayTap,
    required this.onReviewTap,
    required this.onRosterTap,
  });

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('d MMM, h:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = session['attendanceCount'] as int? ?? 0;
    final startedAt = _formatDate(session['startedAt'] as String?);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Status dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.successColor : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isActive ? 'LIVE' : 'CLOSED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive ? AppTheme.successColor : Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  startedAt,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Course
            Text(
              session['courseCode'] as String? ?? '',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              session['courseName'] as String? ?? '',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Stats row
            Row(
              children: [
                _infoBadge(Icons.people, '$count present', AppTheme.primaryColor),
                const SizedBox(width: 8),
                _infoBadge(Icons.timer_outlined, '${session['qrRotationSeconds'] ?? 10}s QR', Colors.grey),
                const SizedBox(width: 8),
                _infoBadge(Icons.radar, '${session['geofenceRadiusMeters'] ?? '?'}m fence', Colors.grey),
              ],
            ),
            const SizedBox(height: 16),

            // Actions
            if (isActive)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.tv, size: 16),
                      label: const Text('Display QR'),
                      onPressed: onDisplayTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.people_outline, size: 16),
                      label: const Text('Roster'),
                      onPressed: onRosterTap,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.people_outline, size: 16),
                      label: const Text('View Roster'),
                      onPressed: onRosterTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.rate_review_outlined, size: 16),
                      label: const Text('Review Queue'),
                      onPressed: onReviewTap,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ─── Attendance Roster Modal ──────────────────────────────────────────────────
class _AttendanceRosterModal extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;

  const _AttendanceRosterModal({required this.session});

  @override
  ConsumerState<_AttendanceRosterModal> createState() => _AttendanceRosterModalState();
}

class _AttendanceRosterModalState extends ConsumerState<_AttendanceRosterModal> {
  List<Map<String, dynamic>> _attendees = [];
  bool _isLoading = true;
  String _filter = 'ALL';
  String _searchQuery = '';
  StompClient? _stompClient;
  bool _isLive = false;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    // Connect WebSocket for live feed only on ACTIVE sessions
    if (widget.session['status'] == 'ACTIVE') {
      _connectStomp();
    }
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    super.dispose();
  }

  void _connectStomp() {
    const storage = FlutterSecureStorage();
    Future.microtask(() async {
      final token = await storage.read(key: 'access_token');
      final sessionId = widget.session['id'] as String;
      _stompClient = StompClient(
        config: StompConfig(
          url: 'ws://localhost:8080/ws',
          onConnect: (frame) {
            if (!mounted) return;
            setState(() => _isLive = true);
            _stompClient!.subscribe(
              destination: '/topic/session/$sessionId/attendance',
              callback: (frame) {
                if (!mounted || frame.body == null) return;
                try {
                  // Parse minimal JSON: {scanId, studentName, finalStatus, submittedAt}
                  final body = frame.body!;
                  final nameMatch = RegExp(r'"studentName"\s*:\s*"([^"]+)"').firstMatch(body);
                  final statusMatch = RegExp(r'"finalStatus"\s*:\s*"([^"]+)"').firstMatch(body);
                  final timeMatch = RegExp(r'"submittedAt"\s*:\s*"([^"]+)"').firstMatch(body);
                  final scanIdMatch = RegExp(r'"scanId"\s*:\s*"([^"]+)"').firstMatch(body);

                  if (nameMatch != null && statusMatch != null) {
                    final newEntry = {
                      'scanId': scanIdMatch?.group(1) ?? '',
                      'studentName': nameMatch.group(1)!,
                      'studentEmail': '',
                      'studentId': '',
                      'finalStatus': statusMatch.group(1)!,
                      'submittedAt': timeMatch?.group(1),
                      'layerResults': <dynamic>[],
                    };
                    setState(() {
                      // Prepend the new entry so newest is at top
                      _attendees = [newEntry, ..._attendees];
                    });
                  }
                } catch (_) {}
              },
            );
          },
          onDisconnect: (_) {
            if (mounted) setState(() => _isLive = false);
          },
          onStompError: (_) {
            if (mounted) setState(() => _isLive = false);
          },
          onWebSocketError: (_) {
            if (mounted) setState(() => _isLive = false);
          },
          connectionTimeout: const Duration(seconds: 5),
          stompConnectHeaders: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
          webSocketConnectHeaders: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      _stompClient!.activate();
    });
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    try {
      final sessionId = widget.session['id'] as String;
      final data = await ref.read(apiClientProvider).getAttendance(sessionId);
      if (mounted) {
        setState(() {
          _attendees = List<Map<String, dynamic>>.from(data['content'] ?? []);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredAttendees {
    return _attendees.where((a) {
      final statusMatch = _filter == 'ALL' || a['finalStatus'] == _filter;
      final name = (a['studentName'] ?? '').toString().toLowerCase();
      final email = (a['studentEmail'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final searchMatch = query.isEmpty || name.contains(query) || email.contains(query);
      return statusMatch && searchMatch;
    }).toList();
  }

  void _exportCsv() {
    if (_attendees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No attendance records to export.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Student Name,Student Email,Status,Submitted At');
    for (final a in _attendees) {
      buffer.writeln('"${a['studentName'] ?? ''}","${a['studentEmail'] ?? ''}","${a['finalStatus'] ?? ''}","${a['submittedAt'] ?? ''}"');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Attendance exported! CSV copied to clipboard.'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'PRESENT':
        return AppTheme.successColor;
      case 'FLAGGED':
        return AppTheme.warningColor;
      case 'REJECTED':
        return AppTheme.errorColor;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseCode = widget.session['courseCode'] ?? 'Session';
    final courseName = widget.session['courseName'] ?? '';
    final isActive = widget.session['status'] == 'ACTIVE';
    final presentCount = _attendees.where((a) => a['finalStatus'] == 'PRESENT').length;
    final flaggedCount = _attendees.where((a) => a['finalStatus'] == 'FLAGGED').length;
    final rejectedCount = _attendees.where((a) => a['finalStatus'] == 'REJECTED').length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('$courseCode — Attendance Roster',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            if (isActive) ...[
                              const SizedBox(width: 10),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _isLive
                                      ? AppTheme.successColor.withValues(alpha: 0.15)
                                      : Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _isLive
                                        ? AppTheme.successColor.withValues(alpha: 0.4)
                                        : Colors.orange.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: _isLive ? AppTheme.successColor : Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isLive ? 'LIVE' : 'Connecting...',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _isLive ? AppTheme.successColor : Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (courseName.isNotEmpty)
                          Text(courseName, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Export CSV'),
                    onPressed: _exportCsv,
                  ),
                ],
              ),
            ),

            // Stat Badges
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  _statChip('Present', '$presentCount', AppTheme.successColor),
                  const SizedBox(width: 8),
                  _statChip('Flagged', '$flaggedCount', AppTheme.warningColor),
                  const SizedBox(width: 8),
                  _statChip('Rejected', '$rejectedCount', AppTheme.errorColor),
                  const SizedBox(width: 8),
                  _statChip('Total', '${_attendees.length}', AppTheme.primaryColor),
                ],
              ),
            ),

            // Search Bar & Filter Chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by student name or email...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['ALL', 'PRESENT', 'FLAGGED', 'REJECTED'].map((f) {
                        final isSelected = _filter == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(f, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : null)),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryColor,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Attendees list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredAttendees.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('No attendees found', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: _filteredAttendees.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _filteredAttendees[index];
                            final name = item['studentName'] ?? 'Unknown';
                            final email = item['studentEmail'] ?? '';
                            final status = item['finalStatus'] as String? ?? 'UNKNOWN';
                            final time = item['submittedAt'] != null
                                ? DateFormat('h:mm:ss a').format(DateTime.parse(item['submittedAt']).toLocal())
                                : '';
                            final layers = List<Map<String, dynamic>>.from(item['layerResults'] ?? []);

                            return ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('$email • $time', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: _statusColor(status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Verification Layer Breakdown:',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      if (layers.isEmpty)
                                        const Text('No layer telemetry recorded', style: TextStyle(fontSize: 11, color: Colors.grey))
                                      else
                                        ...layers.map((l) {
                                          final passed = l['passed'] as bool? ?? false;
                                          final layerName = l['layer'] ?? '';
                                          final detail = l['detail'] ?? '';
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  passed ? Icons.check_circle : Icons.cancel,
                                                  size: 14,
                                                  color: passed ? AppTheme.successColor : AppTheme.errorColor,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(layerName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    detail,
                                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}
