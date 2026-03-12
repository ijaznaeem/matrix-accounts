import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/providers.dart';
import '../../core/providers/sync_providers.dart';
import '../../core/widgets/sync_button.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _isLoadingStatus = false;
  String? _deviceId;
  int? _lastSyncVersion;
  int? _currentVersion;
  int? _pendingChanges;

  // Server login state
  bool _isLoggedIn = false;
  bool _isLoggingIn = false;
  String? _serverEmail;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _checkAuthStatus() {
    final apiClient = ref.read(apiClientProvider);
    setState(() {
      _isLoggedIn = apiClient.token != null;
      _serverEmail = apiClient.prefs.getString('server_email');
    });
  }

  Future<void> _handleServerLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoggingIn = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/api/auth/login', {
        'email': email,
        'password': password,
      });
      if (response['success'] == true && response['token'] != null) {
        await apiClient.prefs.setString('auth_token', response['token']);
        await apiClient.prefs.setString('server_email', email);
        setState(() {
          _isLoggedIn = true;
          _serverEmail = email;
        });
        _emailController.clear();
        _passwordController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logged in to sync server successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadSyncStatus();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Login failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot reach server: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _handleServerLogout() async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.prefs.remove('auth_token');
    await apiClient.prefs.remove('server_email');
    setState(() {
      _isLoggedIn = false;
      _serverEmail = null;
    });
  }

  Future<void> _loadSyncStatus() async {
    final currentCompany = ref.read(currentCompanyProvider);
    if (currentCompany == null) return;

    setState(() => _isLoadingStatus = true);

    try {
      final syncService = ref.read(syncServiceProvider);
      _deviceId = syncService.deviceId;
      _lastSyncVersion = syncService.lastSyncVersion;

      final status = await syncService.getSyncStatus(currentCompany.id);
      if (status != null && mounted) {
        setState(() {
          _currentVersion = status.currentVersion;
          _pendingChanges = status.pendingChanges;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sync status: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStateProvider);
    final currentCompany = ref.watch(currentCompanyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Settings'),
      ),
      body: currentCompany == null
          ? const Center(
              child: Text('Please select a company first'),
            )
          : RefreshIndicator(
              onRefresh: _loadSyncStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Sync Status Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Sync Status',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Spacer(),
                              SyncStatusIndicator(),
                            ],
                          ),
                          const Divider(height: 24),
                          _buildInfoRow('Device ID', _deviceId ?? 'Loading...'),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            'Last Sync Version',
                            _lastSyncVersion?.toString() ?? '0',
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            'Server Version',
                            _currentVersion?.toString() ?? 'Unknown',
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            'Pending Changes',
                            _pendingChanges?.toString() ?? 'Unknown',
                          ),
                          if (syncState.lastSyncTime != null) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              'Last Sync',
                              _formatDateTime(syncState.lastSyncTime!),
                            ),
                          ],
                          if (syncState.state == SyncState.error &&
                              syncState.message != null) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    syncState.message!,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Server Authentication Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isLoggedIn ? Icons.cloud_done : Icons.cloud_off,
                                size: 20,
                                color: _isLoggedIn ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Server Account',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          if (_isLoggedIn) ...([
                            Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Signed in as ${_serverEmail ?? 'Unknown'}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _handleServerLogout,
                                icon: const Icon(Icons.logout, size: 18),
                                label: const Text('Sign Out from Server'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                              ),
                            ),
                          ]) else ...[
                            Text(
                              'Sign in with your server account to enable sync.\nServer: ${AppConfig.apiBaseUrl}',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: Icon(_passwordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () => setState(
                                      () => _passwordVisible = !_passwordVisible),
                                ),
                              ),
                              obscureText: !_passwordVisible,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _handleServerLogin(),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isLoggingIn ? null : _handleServerLogin,
                                icon: _isLoggingIn
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.login),
                                label: Text(_isLoggingIn ? 'Signing in...' : 'Sign In to Server'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sync Actions Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.sync, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Sync Actions',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: SyncButton(
                              onSyncComplete: _loadSyncStatus,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _loadSyncStatus,
                              icon: _isLoadingStatus
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: const Text('Refresh Status'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.help_outline, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'About Sync',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          const Text(
                            'Sync keeps your data synchronized with the cloud server. '
                            'All changes made on this device will be uploaded, and changes '
                            'from other devices will be downloaded.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Company: ${true}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            currentCompany.name,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minute${diff.inMinutes > 1 ? 's' : ''} ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
          '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}
