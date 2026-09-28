import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';

import 'file_store.dart';
import 'pdf_service.dart';
import 'pdf_viewer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const PDFMateApp());
}

class PDFMateApp extends StatelessWidget {
  const PDFMateApp({super.key});

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
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
    _banner = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _banner = null);
        },
      ),
    )..load();
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() => _runFileTask('Scan', _service.scanDocument);

  Future<void> _imagesToPdf() =>
      _runFileTask('Image to PDF', _service.imagesToPdf);

  Future<void> _compress() =>
      _runFileTask('Compression', _service.compressPdf);

  Future<void> _merge() => _runFileTask('Merge', _service.mergePdfs);

  Future<void> _rotate() =>
      _runFileTask('Rotate', _service.rotateAllPages);

  Future<void> _protect() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Protect PDF'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Password',
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
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Protect'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null) return;
    await _runFileTask(
      'Password protection',
      () => _service.passwordProtect(password),
    );
  }

  Future<void> _split() async {
    setState(() => _busy = true);
    try {
      final outputs = await _service.splitEveryPage();
      for (final output in outputs) {
        await _register(output);
      }
      if (!mounted || outputs.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${outputs.length} split PDFs')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Split failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ocr() async {
    setState(() => _busy = true);
    try {
      final text = await _service.ocrImage();
      if (!mounted || text == null) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Extracted text'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text.isEmpty ? 'No text detected.' : text,
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
          SnackBar(content: Text('OCR failed: $e')),
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
                        onTap: _busy ? null : _imagesToPdf,
                      ),
                      _ToolCard(
                        icon: Icons.compress_rounded,
                        title: 'Compress PDF',
                        onTap: _busy ? null : _compress,
                      ),
                      _ToolCard(
                        icon: Icons.call_merge_rounded,
                        title: 'Merge PDF',
                        onTap: _busy ? null : _merge,
                      ),
                      _ToolCard(
                        icon: Icons.content_cut_rounded,
                        title: 'Split PDF',
                        onTap: _busy ? null : _split,
                      ),
                      _ToolCard(
                        icon: Icons.rotate_right_rounded,
                        title: 'Rotate PDF',
                        onTap: _busy ? null : _rotate,
                      ),
                      _ToolCard(
                        icon: Icons.lock_rounded,
                        title: 'Protect PDF',
                        onTap: _busy ? null : _protect,
                      ),
                      _ToolCard(
                        icon: Icons.text_snippet_outlined,
                        title: 'OCR image',
                        onTap: _busy ? null : _ocr,
                      ),
                      _ToolCard(
                        icon: Icons.visibility_rounded,
                        title: 'PDF viewer',
                        onTap: _files.isEmpty ? null : () => _open(_files.first),
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
                              if (value == 'rename') _rename(item);
                              if (value == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'share',
                                child: Text('Share'),
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
  });

  final IconData icon;
  final String title;
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
              const Text(
                'Working',
                style: TextStyle(fontSize: 12),
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
