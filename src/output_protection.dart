import 'package:flutter/material.dart';

/// Editing a decrypted input must never silently export a plaintext copy.
Future<bool> confirmUnprotectedOutput(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create an unprotected copy?'),
        content: const Text('This operation removes the input PDF password and permissions from the new copy. '
          'If auto-save is enabled, that unprotected copy also goes to Downloads. '
          'The original stays protected. Cancel to keep the document protected, or explicitly continue.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create unprotected copy')),
        ],
      ),
    ) ?? false;
