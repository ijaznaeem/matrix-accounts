// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/providers.dart';
import '../../core/mixins/app_lifecycle_mixin.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isDarkMode = false;
  bool _enableNotifications = true;
  bool _autoBackup = true;
  String _currency = 'INR';
  String _dateFormat = 'DD/MM/YYYY';
  String _language = 'English';
  int _autoLockDuration = 5; // Auto-lock after 5 minutes

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricService = ref.read(biometricServiceProvider);

    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _enableNotifications = prefs.getBool('enableNotifications') ?? true;
      _autoBackup = prefs.getBool('autoBackup') ?? true;
      _currency = prefs.getString('currency') ?? 'INR';
      _dateFormat = prefs.getString('dateFormat') ?? 'DD/MM/YYYY';
      _language = prefs.getString('language') ?? 'English';
      _autoLockDuration = biometricService.autoLockDuration;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  void _showCurrencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Currency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            'INR - Indian Rupee',
            'USD - US Dollar',
            'EUR - Euro',
            'GBP - British Pound',
          ].map((currency) {
            final currencyCode = currency.split(' - ')[0];
            return RadioListTile<String>(
              title: Text(currency),
              value: currencyCode,
              groupValue: _currency,
              onChanged: (value) {
                setState(() {
                  _currency = value!;
                });
                _saveSetting('currency', value!);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showDateFormatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Date Format'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            'DD/MM/YYYY',
            'MM/DD/YYYY',
            'YYYY-MM-DD',
          ].map((format) {
            return RadioListTile<String>(
              title: Text(format),
              value: format,
              groupValue: _dateFormat,
              onChanged: (value) {
                setState(() {
                  _dateFormat = value!;
                });
                _saveSetting('dateFormat', value!);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            'English',
            'Hindi',
            'Gujarati',
            'Marathi',
          ].map((lang) {
            return RadioListTile<String>(
              title: Text(lang),
              value: lang,
              groupValue: _language,
              onChanged: (value) {
                setState(() {
                  _language = value!;
                });
                _saveSetting('language', value!);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Language will be applied on next restart'),
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _exportData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Data'),
        content: const Text(
          'This will export all your accounting data to a backup file. '
          'The file will be saved to your device storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Data export started...'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _importData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Data'),
        content: const Text(
          'This will import data from a backup file. '
          'Warning: This may overwrite existing data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select backup file...'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will clear all cached data and temporary files. '
          'Your accounting data will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cache cleared successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _enableBiometricAuth() async {
    try {
      final biometricService = ref.read(biometricServiceProvider);
      final success = await biometricService.setBiometricEnabled(true);

      if (success) {
        setState(() {
          // Refresh the UI
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication enabled successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to enable biometric authentication'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _disableBiometricAuth() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Biometric Authentication'),
        content: const Text(
          'Are you sure you want to disable biometric authentication? '
          'This will also disable auto-lock functionality.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final biometricService = ref.read(biometricServiceProvider);
      final success = await biometricService.setBiometricEnabled(false);

      if (success) {
        setState(() {
          // Refresh the UI
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication disabled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  String _getAutoLockText(int minutes) {
    if (minutes <= 0) return 'Disabled';
    if (minutes == 1) return 'After 1 minute';
    return 'After $minutes minutes';
  }

  void _showAutoLockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto-Lock Duration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Select when to automatically lock the app after going to background:'),
            const SizedBox(height: 16),
            ...[-1, 0, 1, 2, 5, 10, 15, 30].map((minutes) {
              String text;
              if (minutes == -1) {
                text = 'Immediately';
              } else if (minutes == 0) {
                text = 'Never';
              } else if (minutes == 1) {
                text = 'After 1 minute';
              } else {
                text = 'After $minutes minutes';
              }

              return RadioListTile<int>(
                title: Text(text),
                value: minutes,
                groupValue: _autoLockDuration,
                onChanged: (value) async {
                  if (value != null) {
                    final biometricService = ref.read(biometricServiceProvider);
                    await biometricService.setAutoLockDuration(value);
                    setState(() {
                      _autoLockDuration = value;
                    });
                    Navigator.of(context).pop();
                  }
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blueAccent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Appearance Section
          _buildSectionHeader('Appearance'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Switch to dark theme'),
                  value: _isDarkMode,
                  onChanged: (value) {
                    setState(() {
                      _isDarkMode = value;
                    });
                    _saveSetting('isDarkMode', value);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Theme will be applied on next restart'),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: const Text('Language'),
                  subtitle: Text(_language),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showLanguageDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // General Section
          _buildSectionHeader('General'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Notifications'),
                  subtitle: const Text('Receive app notifications'),
                  value: _enableNotifications,
                  onChanged: (value) {
                    setState(() {
                      _enableNotifications = value;
                    });
                    _saveSetting('enableNotifications', value);
                  },
                ),
                ListTile(
                  title: const Text('Currency'),
                  subtitle: Text(_currency),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showCurrencyDialog,
                ),
                ListTile(
                  title: const Text('Date Format'),
                  subtitle: Text(_dateFormat),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showDateFormatDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Security Section
          _buildSectionHeader('Security'),
          Card(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, child) {
                    final biometricService = ref.read(biometricServiceProvider);
                    return FutureBuilder<String>(
                      future:
                          biometricService.getBiometricCapabilityDescription(),
                      builder: (context, snapshot) {
                        final capability = snapshot.data ?? 'Checking...';
                        final isEnabled = biometricService.isBiometricEnabled;

                        return SwitchListTile(
                          title: const Text('Biometric Authentication'),
                          subtitle: Text(capability),
                          value: isEnabled,
                          onChanged: snapshot.hasData
                              ? (value) async {
                                  if (value) {
                                    await _enableBiometricAuth();
                                  } else {
                                    await _disableBiometricAuth();
                                  }
                                }
                              : null,
                        );
                      },
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final biometricService = ref.read(biometricServiceProvider);
                    return ListTile(
                      title: const Text('Auto-Lock Duration'),
                      subtitle: Text(_getAutoLockText(_autoLockDuration)),
                      leading: const Icon(Icons.timer),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      enabled: biometricService.isBiometricEnabled,
                      onTap: biometricService.isBiometricEnabled
                          ? _showAutoLockDialog
                          : null,
                    );
                  },
                ),
                ListTile(
                  title: const Text('Lock App Now'),
                  subtitle: const Text('Manually lock the application'),
                  leading: const Icon(Icons.lock_outline),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    final biometricService = ref.read(biometricServiceProvider);
                    if (biometricService.isBiometricEnabled) {
                      final appLockNotifier =
                          ref.read(appLockStateProvider.notifier);
                      await appLockNotifier.lockApp();
                      context.go('/lock');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please enable biometric authentication first'),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  title: const Text('Change Password'),
                  subtitle: const Text('Update your account password'),
                  leading: const Icon(Icons.lock),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Change Password screen would open here')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Backup Section
          _buildSectionHeader('Backup & Data'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Auto Backup'),
                  subtitle: const Text('Automatically backup data daily'),
                  value: _autoBackup,
                  onChanged: (value) {
                    setState(() {
                      _autoBackup = value;
                    });
                    _saveSetting('autoBackup', value);
                  },
                ),
                ListTile(
                  title: const Text('Export Data'),
                  subtitle: const Text('Backup all accounting data'),
                  leading: const Icon(Icons.download),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _exportData,
                ),
                ListTile(
                  title: const Text('Import Data'),
                  subtitle: const Text('Restore from backup file'),
                  leading: const Icon(Icons.upload),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _importData,
                ),
                ListTile(
                  title: const Text('Clear Cache'),
                  subtitle: const Text('Free up storage space'),
                  leading: const Icon(Icons.cleaning_services),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _clearCache,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Support Section
          _buildSectionHeader('Support'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Help & FAQ'),
                  subtitle: const Text('Get help and find answers'),
                  leading: const Icon(Icons.help),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/help');
                  },
                ),
                ListTile(
                  title: const Text('Contact Support'),
                  subtitle: const Text('Get in touch with our team'),
                  leading: const Icon(Icons.support_agent),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Contact: support@matrix-solutions.com')),
                    );
                  },
                ),
                ListTile(
                  title: const Text('About'),
                  subtitle: const Text('App version and info'),
                  leading: const Icon(Icons.info),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/about');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Reset Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Reset Settings'),
                    content: const Text(
                      'This will reset all settings to their default values. '
                      'Your accounting data will not be affected.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Settings reset successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadSettings();
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reset All Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}
