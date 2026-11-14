// Dialog that asks for a name (scripts, folders, notes) and checks it.

import 'package:flutter/material.dart';

Future<String?> askName(BuildContext context, String title,
    {String initial = '', String? Function(String)? validate}) {
  final ctrl = TextEditingController(text: initial);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final err = validate?.call(ctrl.text);
          if (err != null) {
            setState(() => error = err);
          } else {
            Navigator.pop(ctx, ctrl.text);
          }
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 340,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Имя', errorText: error),
              onSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      },
    ),
  );
}

// ------------------------------------------------------------------- scripts
