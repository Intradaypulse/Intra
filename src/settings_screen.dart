import 'package:flutter/material.dart';

import 'ads_service.dart';
import 'privacy_policy_screen.dart';
import 'telemetry_service.dart';
import 'signature_backup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.autoSaveDownloads,
    required this.onThemeChanged,
    required this.onAutoSaveChanged,
  });

  final ThemeMode themeMode;
  final bool autoSaveDownloads;
  final Future<void> Function(ThemeMode mode) onThemeChanged;
  final Future<void> Function(bool value) onAutoSaveChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themeMode = widget.themeMode;
  late bool _autoSaveDownloads = widget.autoSaveDownloads;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) _themeMode = widget.themeMode;
    if (oldWidget.autoSaveDownloads != widget.autoSaveDownloads) {
      _autoSaveDownloads = widget.autoSaveDownloads;
    }
  }

  Future<void> _save(Future<void> Function() write, VoidCallback apply) async {
    if (_saving || !mounted) return;
    setState(() => _saving = true);
    try {
      await write();
      if (mounted) setState(apply);
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save settings. Please retry.')),
      );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Theme'),
              subtitle: Text(_themeLabel(_themeMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving ? null : () async {
                final value = await showModalBottomSheet<ThemeMode>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: RadioGroup<ThemeMode>(
                      groupValue: _themeMode,
                      onChanged: (selected) {
                        if (selected != null) {
                          Navigator.pop(context, selected);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final mode in ThemeMode.values)
                            RadioListTile<ThemeMode>(
                              value: mode,
                              title: Text(_themeLabel(mode)),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
                if (value != null && mounted) {
                  await _save(() => widget.onThemeChanged(value),
                      () => _themeMode = value);
                }
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'File safety',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.download_done_rounded),
              value: _autoSaveDownloads,
              onChanged: _saving ? null : (value) => _save(
                () => widget.onAutoSaveChanged(value),
                () => _autoSaveDownloads = value,
              ),
              title: const Text('Auto-save a copy to Downloads'),
              subtitle: const Text(
                'After a PDF is created, keep an extra copy in Download/PDFMate on supported Android versions.',
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Ads & privacy',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('settings_privacy_policy'),
                  leading: const Icon(Icons.policy_outlined),
                  title: const Text('Privacy policy'),
                  subtitle: const Text('Read how documents, ads and diagnostics are handled.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy choices'),
                  subtitle: const Text(
                    'Review or change consent choices used for ads.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: AdsService.instance.privacyOptionsRequired
                      ? AdsService.instance.showPrivacyOptions
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Privacy options are not required for this device/region right now.',
                              ),
                            ),
                          );
                        },
                ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('settings_ad_mode'),
                  leading: const Icon(Icons.ads_click_outlined),
                  title: const Text('Ad mode'),
                  subtitle: Text(
                    AdsService.instance.productionRevenueMode
                        ? 'Production AdMob is active.'
                        : AdsService.instance.productionConfigured
                            ? 'Production IDs configured; revenue activates in the signed release build.'
                            : 'Test / disabled mode. Add all production AdMob IDs before release.',
                  ),
                  trailing: Icon(
                    AdsService.instance.productionConfigured
                        ? Icons.verified_rounded
                        : Icons.warning_amber_rounded,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('settings_firebase_status'),
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('Firebase services'),
                  subtitle: Text(
                    TelemetryService.instance.enabled
                        ? 'Analytics, Crashlytics and Remote Config are active.'
                        : TelemetryService.instance.configurationPresent
                            ? 'Firebase is configured but did not initialize in this session.'
                            : 'Not configured. Production release requires Firebase project values.',
                  ),
                  trailing: Icon(
                    TelemetryService.instance.enabled
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('Signature backup'),
            subtitle: const Text('Save or restore your reusable signatures'),
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => const SignatureBackupScreen()))),
          Text(
            'About',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.picture_as_pdf_rounded),
                  title: Text('ScanLumo'),
                  subtitle: Text('Advanced beta • on-device PDF toolkit'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.security_rounded),
                  title: Text('Document processing'),
                  subtitle: Text(
                    'Core PDF edits, scanning and OCR are designed to run locally on the device.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
