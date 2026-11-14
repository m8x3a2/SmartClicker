// Line-by-line difference of two texts (the window "Differences" on
// import): the longest common subsequence of lines, no packages.

enum DiffKind { same, removed, added }

class DiffLine {
  final DiffKind kind;
  final String text;

  /// Line numbers in the old and the new text (0 — not there).
  final int oldLine, newLine;
  const DiffLine(this.kind, this.text, this.oldLine, this.newLine);
}

/// The lines of [before] and [after] in order: kept, removed and added.
/// Very long texts (over [maxLines] lines each) are compared line by line
/// in place, without looking for moved blocks.
List<DiffLine> lineDiff(String before, String after, {int maxLines = 3000}) {
  // Windows line ends (\r\n) and Unix ones (\n) are the same lines.
  final a = before.replaceAll('\r\n', '\n').split('\n'), b = after.replaceAll('\r\n', '\n').split('\n');
  // Common start and end are cut off first: usually only a little changed.
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  final out = <DiffLine>[
    for (var i = 0; i < start; i++) DiffLine(DiffKind.same, a[i], i + 1, i + 1),
  ];
  final n = endA - start, m = endB - start;
  if (n > maxLines || m > maxLines) {
    for (var i = start; i < endA; i++) {
      out.add(DiffLine(DiffKind.removed, a[i], i + 1, 0));
    }
    for (var j = start; j < endB; j++) {
      out.add(DiffLine(DiffKind.added, b[j], 0, j + 1));
    }
  } else {
    // lcs[i][j] — the common length of a[start+i..] and b[start+j..].
    final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i][j] = a[start + i] == b[start + j]
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n || j < m) {
      if (i < n && j < m && a[start + i] == b[start + j]) {
        out.add(DiffLine(DiffKind.same, a[start + i], start + i + 1, start + j + 1));
        i++;
        j++;
      } else if (i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1])) {
        out.add(DiffLine(DiffKind.removed, a[start + i], start + i + 1, 0)); // removed first
        i++;
      } else {
        out.add(DiffLine(DiffKind.added, b[start + j], 0, start + j + 1));
        j++;
      }
    }
  }
  for (var k = 0; k < a.length - endA; k++) {
    out.add(DiffLine(DiffKind.same, a[endA + k], endA + k + 1, endB + k + 1));
  }
  return out;
}
