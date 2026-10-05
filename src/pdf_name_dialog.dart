import 'package:flutter/material.dart';

Future<String?> askPdfName(BuildContext context, {required String initialName}) =>
  showDialog<String>(context: context, builder: (_) => _NameDialog(initialName));

class _NameDialog extends StatefulWidget {
  const _NameDialog(this.initialName);
  final String initialName;
  @override State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename PDF'),
    content: TextField(controller: _controller, autofocus: true,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(suffixText: '.pdf', border: OutlineInputBorder())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: const Text('Rename')),
    ],
  );
}
