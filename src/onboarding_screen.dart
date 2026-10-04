import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _items = [
    (
      icon: Icons.document_scanner_rounded,
      title: 'Scan documents cleanly',
      body:
          'Live edge detection, auto-capture, manual corner correction and multi-page scanning.',
    ),
    (
      icon: Icons.build_circle_outlined,
      title: 'Powerful PDF tools',
      body:
          'Compress, merge, split, organize, OCR, sign, protect and convert PDFs on-device.',
    ),
    (
      icon: Icons.privacy_tip_outlined,
      title: 'Your files stay under your control',
      body:
          'Core document processing runs locally. You can auto-save copies to Download/PDFMate for extra file safety.',
    ),
  ];

  Future<void> _next() async {
    if (_finishing) return;
    if (_page < _items.length - 1) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await widget.onFinished();
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save onboarding. Please retry.')),
      );
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finishing ? null : _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _items.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Icon(
                            item.icon,
                            size: 58,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          item.body,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == _page ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: i == _page
                                ? colors.primary
                                : colors.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _finishing ? null : _next,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          _page == _items.length - 1
                              ? 'Start using ScanLumo'
                              : 'Continue',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
