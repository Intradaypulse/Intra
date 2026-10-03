import 'package:flutter/material.dart';

Future<String?> askPdfPassword(BuildContext context, {
  String title = 'PDF password', String label = 'Password',
}) => showDialog<String>(context: context, barrierDismissible: false,
  builder: (_) => _PdfPasswordDialog(title: title, label: label));

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog({required this.title, required this.label});
  final String title;
  final String label;
  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: _controller, obscureText: true, autofocus: true,
      decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Open')),
    ],
  );
}
