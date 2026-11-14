// Colours of message levels (ok, warn, error, info) shared by the screens.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Color levelColor(String level) => switch (level) {
      'ok' => const Color(0xFF3FB950),
      'warn' => const Color(0xFFE3A008),
      'error' => const Color(0xFFE5484D),
      _ => const Color(0xFF6CB6FF),
    };
