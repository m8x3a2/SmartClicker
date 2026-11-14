// Dialog "press a key or a combination" for hotkeys and for key() in blocks.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../../platform/keys.dart';
import '../editor/code_editor.dart';
import 'page_parts.dart';

/// Dialog that waits for a key or a key combination and returns it as
/// "ctrl+alt+s". Returns null when cancelled.
Future<String?> captureHotkey(
  BuildContext context,
  AppController app, {
  bool forScript = false,
}) async {
  app.suspendHotkeys();
  try {
    return await showDialog<String>(
      context: context,
      builder: (_) => _HotkeyDialog(app, forScript: forScript),
    );
  } finally {
    app.resumeHotkeys();
  }
}

class _HotkeyDialog extends StatefulWidget {
  final AppController app;

  /// The key goes into a script (`key("...")`), not into a hotkey.
  final bool forScript;
  const _HotkeyDialog(this.app, {this.forScript = false});

  @override
  State<_HotkeyDialog> createState() => _HotkeyDialogState();
}

class _HotkeyDialogState extends State<_HotkeyDialog> {
  Timer? _timer;
  bool _armed = false; // true once every key from before the dialog is released
  bool _closed = false;
  String _mods = '';

  /// Closes the dialog once. A second pop (Esc seen by the poll while the
  /// dialog was already closing) used to close the main page: black window.
  void _close([String? result]) {
    if (_closed || !mounted) return;
    _closed = true;
    _timer?.cancel();
    Navigator.pop(context, result);
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    if (_closed || !mounted) return;
    final b = widget.app.backend;
    final mods = [
      for (final m in const ['ctrl', 'shift', 'alt', 'win'])
        if (b.isVkDown(vkByName[m]!)) m,
    ];
    String? key;
    for (final vk in recordableVks) {
      final name = nameByVk[vk]!;
      if (modifierKeys.contains(name) || name.contains('+')) continue;
      if (b.isVkDown(vk)) {
        key = name;
        break;
      }
    }
    if (!_armed) {
      if (key == null && mods.isEmpty) _armed = true;
      return;
    }
    if (key != null) {
      _close([...mods, key].join('+'));
      return;
    }
    final shown = mods.join('+');
    if (shown != _mods) setState(() => _mods = shown);
  }

  @override
  Widget build(BuildContext context) {
    // Esc must be a key that can be chosen (e.g. for the stop), so the
    // dialog closes only by "Отмена" or a click outside it.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !widget.app.backend.isVkDown(0x1B)) _close();
      },
      child: AlertDialog(
        title: Text(
          widget.forScript ? 'Какую клавишу нажимать?' : 'Назначить клавишу',
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Нажмите клавишу или сочетание: например F12, Ctrl+Alt+S, Shift+F5.',
              ),
              const SizedBox(height: 14),
              Text(
                _mods.isEmpty ? 'Жду нажатия…' : '${_mods.toUpperCase()}+…',
                style: codeStyle.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 10),
              Text(
                widget.forScript
                    ? 'Клавиша попадёт в блок как текст, например "ctrl+c".'
                    : 'Совет: для аварийной остановки выбирайте одну клавишу, которую легко нажать вслепую.',
                style: const TextStyle(color: mutedText, fontSize: 12.5),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: _close, child: const Text('Отмена'))],
      ),
    );
  }
}

// ------------------------------------------------------------ quick settings
