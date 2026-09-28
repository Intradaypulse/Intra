import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';

import 'advanced_merge_screen.dart';
import 'advanced_split_screen.dart';
import 'compression_screen.dart';
import 'ocr_screen.dart';
import 'onboarding_screen.dart';
import 'page_organizer_screen.dart';
import 'pdf_to_jpg_screen.dart';
import 'security_screen.dart';
import 'settings_screen.dart';
import 'settings_store.dart';
import 'signature_placement_screen.dart';
import 'ads_service.dart';
import 'file_store.dart';
import 'live_scanner_screen.dart';
import 'pdf_service.dart';
import 'pdf_viewer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const PDFMateApp());
}

class PDFMateApp extends StatefulWidget {
  const PDFMateApp({super.key});

  @override
  State<PDFMateApp> createState() => _PDFMateAppState();
}

class _PDFMateAppState extends State<PDFMateApp> {
  final AppSettingsStore _settings = AppSettingsStore();

  bool _ready = false;
  bool _onboardingComplete = false;
  bool _autoSaveDownloads = true;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final values = await Future.wait<Object>([
      _settings.loadThemeMode(),
      _settings.loadAutoSaveDownloads(),
      _settings.isOnboardingComplete(),
    ]);
    if (!mounted) return;
    setState(() {
      _themeMode = values[0] as ThemeMode;
      _autoSaveDownloads = values[1] as bool;
      _onboardingComplete = values[2] as bool;
      _ready = true;
    });
  }

  Future<void> _setTheme(ThemeMode mode) async {
    await _settings.saveThemeMode(mode);
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> _setAutoSave(bool value) async {
    await _settings.saveAutoSaveDownloads(value);
    if (mounted) setState(() => _autoSaveDownloads = value);
  }

  Future<void> _finishOnboarding() async {
    await _settings.completeOnboarding();
    if (mounted) setState(() => _onboardingComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDFMate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF315EF5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6E8BFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: !_ready
          ? const _LaunchScreen()
          : !_onboardingComplete
              ? OnboardingScreen(onFinished: _finishOnboarding)
              : HomeScreen(
                  themeMode: _themeMode,
                  autoSaveDownloads: _autoSaveDownloads,
                  onThemeChanged: _setTheme,
                  onAutoSaveChanged: _setAutoSave,
                ),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                color: colors.onPrimary,
                size: 52,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'PDFMate',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PdfService _service = PdfService();
  final PdfFileStore _store = PdfFileStore();
  final TextEditingController _search = TextEditingController();

  List<PdfRecord> _files = [];
  bool _busy = false;
  BannerAd? _banner;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _search.addListener(() => setState(() {}));
    _initializeAds();
  }

  Future<void> _initializeAds() async {
    await AdsService.instance.initialize();
    if (!mounted) return;
    _banner = AdsService.instance.createBanner(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    setState(() {});
  }

  @override
  void dispose() {
    _banner?.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final files = await _store.load();
    if (mounted) setState(() => _files = files);
  }

  Future<void> _register(File file) async {
    final record = PdfRecord(
      path: file.path,
      name: file.uri.pathSegments.last,
      createdAt: DateTime.now(),
    );
    await _store.add(record);

    if (widget.autoSaveDownloads) {
      try {
        await _service.savePdfToDownloads(file);
      } catch (_) {
        // Keep the internal copy even if public Downloads export is unavailable.
      }
    }

    await _loadFiles();
  }

  Future<void> _runFileTask(
    String label,
    Future<File?> Function() task,
  ) async {
    setState(() => _busy = true);
    try {
      final output = await task();
      if (output == null) return;
      await _register(output);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label complete'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openPath(output.path, output.uri.pathSegments.last),
          ),
        ),
      );
      await AdsService.instance.recordCompletedOperation();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final pages = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const LiveScannerScreen()),
    );
    if (pages == null || pages.isEmpty) return;

    setState(() => _busy = true);
    try {
      final output = await _service.createScannedPdfFromFiles(pages);
      await _register(output);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${pages.length}-page scan'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openPath(
              output.path,
              output.uri.pathSegments.last,
            ),
          ),
        ),
      );
      await AdsService.instance.recordCompletedOperation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      for (final path in pages) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _imagesToPdf() =>
      _runFileTask('Image to PDF', _service.imagesToPdf);

  Future<void> _completeAdvancedFile(
    String label,
    File? output,
  ) async {
    if (output == null) return;
    setState(() => _busy = true);
    try {
      await _register(output);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label complete'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openPath(
              output.path,
              output.uri.pathSegments.last,
            ),
          ),
        ),
      );
      await AdsService.instance.recordCompletedOperation();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compress() async {
    final output = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CompressionScreen(service: _service),
      ),
    );
    await _completeAdvancedFile('Compression', output);
  }

  Future<void> _merge() async {
    final output = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => AdvancedMergeScreen(service: _service),
      ),
    );
    await _completeAdvancedFile('Merge', output);
  }

  Future<void> _split() async {
    final outputs = await Navigator.of(context).push<List<File>>(
      MaterialPageRoute(
        builder: (_) => AdvancedSplitScreen(service: _service),
      ),
    );
    if (outputs == null || outputs.isEmpty) return;

    setState(() => _busy = true);
    try {
      for (final output in outputs) {
        await _register(output);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${outputs.length} split PDF(s)')),
      );
      await AdsService.instance.recordCompletedOperation();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _organize() async {
    final output = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => PageOrganizerScreen(service: _service),
      ),
    );
    await _completeAdvancedFile('Page organization', output);
  }

  Future<void> _signPdf() async {
    final output = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => SignaturePlacementScreen(service: _service),
      ),
    );
    await _completeAdvancedFile('Signature', output);
  }

  Future<void> _security(SecurityMode mode) async {
    final output = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => SecurityScreen(
          service: _service,
          initialMode: mode,
        ),
      ),
    );
    await _completeAdvancedFile(
      mode == SecurityMode.protect ? 'PDF protection' : 'PDF unlock',
      output,
    );
  }

  Future<void> _ocrPdf() async {
    final output = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => OcrScreen(service: _service),
      ),
    );
    await _completeAdvancedFile('Searchable PDF', output);
  }

  Future<void> _pdfToJpg() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfToJpgScreen(service: _service),
      ),
    );
  }

  Future<void> _extractPdfText() async {
    setState(() => _busy = true);
    try {
      final text = await _service.extractPdfText();
      if (!mounted || text == null) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Embedded PDF text'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text.trim().isEmpty
                    ? 'No embedded text found. Use OCR for scanned pages.'
                    : text,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Text extraction failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  void _open(PdfRecord record) => _openPath(record.path, record.name);

  void _openPath(String path, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(path: path, title: title),
      ),
    );
  }

  Future<void> _share(PdfRecord record) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(record.path)],
        text: 'Created with PDFMate',
      ),
    );
  }


  Future<void> _export(PdfRecord record) async {
    try {
      final uri = await _service.exportPdf(File(record.path), record.name);
      if (!mounted || uri == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF exported successfully')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _rename(PdfRecord record) async {
    final current = record.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            suffixText: '.pdf',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    final source = File(record.path);
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_');
    final newPath = '${source.parent.path}/$safe.pdf';
    final renamed = await source.rename(newPath);
    await _store.replace(
      record.path,
      record.copyWith(
        path: renamed.path,
        name: '$safe.pdf',
      ),
    );
    await _loadFiles();
  }

  Future<void> _delete(PdfRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete PDF?'),
        content: Text(record.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final file = File(record.path);
    if (await file.exists()) await file.delete();
    await _store.remove(record.path);
    await _loadFiles();
  }

  List<PdfRecord> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _files;
    return _files.where((e) => e.name.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final files = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf_rounded),
            SizedBox(width: 10),
            Text('PDFMate Beta'),
          ],
        ),
        actions: [
          if (AdsService.instance.privacyOptionsRequired)
            IconButton(
              tooltip: 'Privacy choices',
              onPressed: AdsService.instance.showPrivacyOptions,
              icon: const Icon(Icons.privacy_tip_outlined),
            ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    themeMode: widget.themeMode,
                    autoSaveDownloads: widget.autoSaveDownloads,
                    onThemeChanged: widget.onThemeChanged,
                    onAutoSaveChanged: widget.onAutoSaveChanged,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _loadFiles,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.primary, color.primaryContainer],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan. Edit. Share.',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: color.onPrimary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Core PDF tools now work on-device.',
                          style: TextStyle(color: color.onPrimary),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: color.surface,
                              foregroundColor: color.primary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _busy ? null : _scan,
                            icon: const Icon(Icons.document_scanner_rounded),
                            label: const Text('Scan document'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'PDF tools',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.42,
                    children: [
                      _ToolCard(
                        icon: Icons.image_rounded,
                        title: 'Image to PDF',
                        subtitle: 'File-backed',
                        onTap: _busy ? null : _imagesToPdf,
                      ),
                      _ToolCard(
                        icon: Icons.compress_rounded,
                        title: 'Compress PDF',
                        subtitle: '3 quality levels',
                        onTap: _busy ? null : _compress,
                      ),
                      _ToolCard(
                        icon: Icons.call_merge_rounded,
                        title: 'Merge PDF',
                        subtitle: 'Preview + reorder',
                        onTap: _busy ? null : _merge,
                      ),
                      _ToolCard(
                        icon: Icons.content_cut_rounded,
                        title: 'Split PDF',
                        subtitle: 'Ranges / every N',
                        onTap: _busy ? null : _split,
                      ),
                      _ToolCard(
                        icon: Icons.view_module_rounded,
                        title: 'Organize pages',
                        subtitle: 'Reorder / rotate / delete',
                        onTap: _busy ? null : _organize,
                      ),
                      _ToolCard(
                        icon: Icons.manage_search_rounded,
                        title: 'OCR PDF',
                        subtitle: 'Multilingual + searchable',
                        onTap: _busy ? null : _ocrPdf,
                      ),
                      _ToolCard(
                        icon: Icons.draw_rounded,
                        title: 'Sign PDF',
                        subtitle: 'Move / resize / rotate',
                        onTap: _busy ? null : _signPdf,
                      ),
                      _ToolCard(
                        icon: Icons.lock_rounded,
                        title: 'Protect PDF',
                        subtitle: 'AES-256 + permissions',
                        onTap: _busy
                            ? null
                            : () => _security(SecurityMode.protect),
                      ),
                      _ToolCard(
                        icon: Icons.lock_open_rounded,
                        title: 'Unlock PDF',
                        subtitle: 'Remove password',
                        onTap: _busy
                            ? null
                            : () => _security(SecurityMode.unlock),
                      ),
                      _ToolCard(
                        icon: Icons.photo_library_outlined,
                        title: 'PDF to JPG',
                        subtitle: 'Preview + Gallery',
                        onTap: _busy ? null : _pdfToJpg,
                      ),
                      _ToolCard(
                        icon: Icons.text_fields_rounded,
                        title: 'Extract text',
                        subtitle: 'Embedded text',
                        onTap: _busy ? null : _extractPdfText,
                      ),
                      _ToolCard(
                        icon: Icons.visibility_rounded,
                        title: 'PDF viewer',
                        subtitle: 'Search + thumbnails',
                        onTap: _files.isEmpty
                            ? null
                            : () => _open(_files.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Search your PDFs',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'My PDFs',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text('${files.length}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (files.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: color.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.folder_open_rounded),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('No saved PDFs yet.'),
                          ),
                        ],
                      ),
                    )
                  else
                    ...files.map(
                      (item) => Card(
                        child: ListTile(
                          onTap: () => _open(item),
                          leading: const CircleAvatar(
                            child: Icon(Icons.picture_as_pdf_rounded),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${item.createdAt.day.toString().padLeft(2, '0')}/'
                            '${item.createdAt.month.toString().padLeft(2, '0')} '
                            '${item.createdAt.hour.toString().padLeft(2, '0')}:'
                            '${item.createdAt.minute.toString().padLeft(2, '0')}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'share') _share(item);
                              if (value == 'export') _export(item);
                              if (value == 'rename') _rename(item);
                              if (value == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'share',
                                child: Text('Share'),
                              ),
                              PopupMenuItem(
                                value: 'export',
                                child: Text('Export / Save As'),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_banner != null) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: SizedBox(
                        width: _banner!.size.width.toDouble(),
                        height: _banner!.size.height.toDouble(),
                        child: AdWidget(ad: _banner!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.camera_alt_rounded),
        label: const Text('Scan'),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle = 'Working',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 30),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Beta core build trigger

// Modular beta pipeline trigger

// Full fix batch build trigger
