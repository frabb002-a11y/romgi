import 'package:flutter/material.dart';

enum AcquireMode { ghost, real }

Future<AcquireMode?> showAcquireModeDialog(
  BuildContext context, {
  required int count,
}) {
  final title = count == 1 ? 'Add this game' : 'Add $count games';
  return showDialog<AcquireMode>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: const Text(
        'A ghost file is an empty file with the link’s own filename, so the '
        'library can list it before the game data is downloaded. Archives '
        'are skipped.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, AcquireMode.ghost),
          child: const Text('Ghost files'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, AcquireMode.real),
          child: const Text('Download game data'),
        ),
      ],
    ),
  );
}
