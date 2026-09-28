import 'package:flutter/material.dart';

import 'ads_service.dart';

class SettingsScreen extends StatelessWidget {
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
              subtitle: Text(_themeLabel(themeMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final value = await showModalBottomSheet<ThemeMode>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final mode in ThemeMode.values)
                          RadioListTile<ThemeMode>(
                            value: mode,
                            groupValue: themeMode,
                            title: Text(_themeLabel(mode)),
                            onChanged: (selected) {
                              if (selected != null) {
                                Navigator.pop(context, selected);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                );
                if (value != null) await onThemeChanged(value);
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
              value: autoSaveDownloads,
              onChanged: onAutoSaveChanged,
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
                const ListTile(
                  leading: Icon(Icons.ads_click_outlined),
                  title: Text('Ad mode'),
                  subtitle: Text(
                    'Testing builds use Google test ad units. Production IDs are injected only for signed release builds.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
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
                  title: Text('PDFMate'),
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
