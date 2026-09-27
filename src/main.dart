import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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

class SavedPdf {
  SavedPdf(this.path, this.name, this.createdAt);
  final String path;
  final String name;
  final DateTime createdAt;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<SavedPdf> _recent = [];
  BannerAd? _banner;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _scanToPdf() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (image == null) return;
    await _makePdf([image], prefix: 'Scan');
  }

  Future<void> _imagesToPdf() async {
    final List<XFile> images = await _picker.pickMultiImage(imageQuality: 92);
    if (images.isEmpty) return;
    await _makePdf(images, prefix: 'Images');
  }

  Future<void> _makePdf(List<XFile> images, {required String prefix}) async {
    setState(() => _busy = true);
    try {
      final document = pw.Document();
      for (final image in images) {
        final Uint8List bytes = await image.readAsBytes();
        final pw.MemoryImage memoryImage = pw.MemoryImage(bytes);
        document.addPage(
          pw.Page(
            margin: const pw.EdgeInsets.all(18),
            build: (_) => pw.Center(
              child: pw.Image(memoryImage, fit: pw.BoxFit.contain),
            ),
          ),
        );
      }

      final Directory dir = await getApplicationDocumentsDirectory();
      final String name =
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final String path = '${dir.path}/$name';
      await File(path).writeAsBytes(await document.save(), flush: true);

      final item = SavedPdf(path, name, DateTime.now());
      if (mounted) {
        setState(() => _recent.insert(0, item));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF created: $name'),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => _share(item),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(SavedPdf item) async {
    await Share.shareXFiles(
      [XFile(item.path)],
      text: 'Created with PDFMate',
    );
  }

  void _comingSoon(String tool) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tool, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'This testing APK verifies installation, UI, camera/image-to-PDF, local saving, sharing and AdMob test ads. This tool is wired in the full build phase.',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf_rounded),
            SizedBox(width: 10),
            Text('PDFMate'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'PDFMate',
              applicationVersion: '0.1 testing',
              children: const [
                Text('Free PDF scanner & utility app — testing build.'),
              ],
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.primary,
                        color.primaryContainer,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your PDF toolkit',
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
                        'Scan or turn photos into a PDF in seconds.',
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
                          onPressed: _busy ? null : _scanToPdf,
                          icon: const Icon(Icons.document_scanner_rounded),
                          label: const Text('Scan document'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Quick tools',
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
                  childAspectRatio: 1.45,
                  children: [
                    _ToolCard(
                      icon: Icons.image_rounded,
                      title: 'Image to PDF',
                      subtitle: 'Working',
                      onTap: _busy ? null : _imagesToPdf,
                    ),
                    _ToolCard(
                      icon: Icons.compress_rounded,
                      title: 'Compress PDF',
                      onTap: () => _comingSoon('Compress PDF'),
                    ),
                    _ToolCard(
                      icon: Icons.call_merge_rounded,
                      title: 'Merge PDF',
                      onTap: () => _comingSoon('Merge PDF'),
                    ),
                    _ToolCard(
                      icon: Icons.content_cut_rounded,
                      title: 'Split PDF',
                      onTap: () => _comingSoon('Split PDF'),
                    ),
                    _ToolCard(
                      icon: Icons.text_snippet_outlined,
                      title: 'OCR',
                      onTap: () => _comingSoon('OCR'),
                    ),
                    _ToolCard(
                      icon: Icons.draw_rounded,
                      title: 'Sign PDF',
                      onTap: () => _comingSoon('Sign PDF'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Recent PDFs',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                if (_recent.isEmpty)
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
                          child: Text(
                            'Create your first PDF and it will appear here.',
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._recent.map(
                    (item) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.picture_as_pdf_rounded),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.createdAt.hour.toString().padLeft(2, '0')}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Share',
                          onPressed: () => _share(item),
                          icon: const Icon(Icons.share_rounded),
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
        onPressed: _busy ? null : _scanToPdf,
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
    this.subtitle = 'Coming next',
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
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Build trigger: PDFMate Android test APK

// PR build trigger

// Synchronize Actions trigger 2
