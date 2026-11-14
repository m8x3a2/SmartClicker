// Small pieces shared by the pages: header with actions, muted text colour, time stamps.

import 'package:flutter/material.dart';

const mutedText = Color(0xFF8B92A1);

Widget pageHeader(String title, {List<Widget> actions = const []}) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          ...actions,
        ],
      ),
    );

String twoDigits(int n) => n.toString().padLeft(2, '0');

String timeStamp(DateTime d) =>
    '${twoDigits(d.day)}.${twoDigits(d.month)} ${twoDigits(d.hour)}:${twoDigits(d.minute)}:${twoDigits(d.second)}';

// --------------------------------------------------------------------- tools
