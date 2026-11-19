import 'dart:math' as math;

import 'match_groups.dart';

/// What changed between two texts, word by word — for the conflict view.
///
/// A plain longest-common-subsequence diff over tokens (words, spaces, punctuation). A
/// family's texts are short; for a very long page it falls back to whole lines, so the
/// table stays small.
enum DiffKind { same, added, removed }

class DiffSegment {
  const DiffSegment(this.kind, this.text);

  final DiffKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffSegment && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}:$text';
}

final _words = RegExp(r'\s+|[\p{L}\p{N}_]+|[^\s\p{L}\p{N}_]', unicode: true);

/// Above this many token pairs the diff works on lines instead of words.
const _maxCells = 2000000;
final _lineEnds = RegExp(r'(?<=\n)');

List<DiffSegment> diffWords(String before, String after) {
  List<String> a = [for (final m in _words.allMatches(before)) m.groupOf(0)];
  List<String> b = [for (final m in _words.allMatches(after)) m.groupOf(0)];
  if (a.length * b.length > _maxCells) {
    a = before.split(_lineEnds);
    b = after.split(_lineEnds);
  }
  return _diff(a, b);
}

List<DiffSegment> _diff(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  // lengths[i][j]: the common subsequence of a[i..] and b[j..].
  final lengths = [for (int i = 0; i <= n; i++) List<int>.filled(m + 1, 0)];
  for (int i = n - 1; i >= 0; i--) {
    for (int j = m - 1; j >= 0; j--) {
      lengths[i][j] = a[i] == b[j]
          ? lengths[i + 1][j + 1] + 1
          : math.max(lengths[i + 1][j], lengths[i][j + 1]);
    }
  }

  final segments = <DiffSegment>[];
  void add(DiffKind kind, String text) {
    if (segments.isNotEmpty && segments.last.kind == kind) {
      segments[segments.length - 1] = DiffSegment(
        kind,
        segments.last.text + text,
      );
    } else {
      segments.add(DiffSegment(kind, text));
    }
  }

  int i = 0;
  int j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      add(DiffKind.same, a[i]);
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      add(DiffKind.removed, a[i++]);
    } else {
      add(DiffKind.added, b[j++]);
    }
  }
  while (i < n) {
    add(DiffKind.removed, a[i++]);
  }
  while (j < m) {
    add(DiffKind.added, b[j++]);
  }
  return segments;
}
