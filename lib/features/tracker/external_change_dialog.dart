import 'package:flutter/material.dart';

Future<bool?> showExternalChangeDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('The CSV changed outside the app.'),
      content: const Text(
        'Load the file and discard your unsaved edits, or keep your edits '
        'and overwrite the file on your next save.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep my edits'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard edits & load file'),
        ),
      ],
    ),
  );
}
