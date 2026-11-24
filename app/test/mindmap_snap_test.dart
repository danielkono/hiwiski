import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/wiki/mindmap_snap.dart';

/// Lining elements up: a moved or resized box snaps to the lines, gaps and sizes of
/// the others within reach, to the grid without one, and a group is aligned,
/// distributed and sized in one go.
void main() {
  group('a moved box', () {
    test('snaps its top to another top, and the guide runs across both', () {
      final result = snapMove(const Rect.fromLTWH(200, 104, 100, 50), [
        const Rect.fromLTWH(0, 100, 100, 80),
      ], reach: 6);
      expect(result.by, equals(const Offset(0, -4)));
      expect(
        result.guides.single,
        equals((vertical: false, at: 100.0, from: 0.0, to: 300.0)),
      );
    });

    test('snaps its middle to another middle, each axis on its own', () {
      final result = snapMove(const Rect.fromLTWH(3, 300, 100, 40), [
        const Rect.fromLTWH(0, 0, 100, 40),
      ], reach: 6);
      // Left to left (and middle to middle, right to right): -3 across, nothing
      // down — 300 is far from any line.
      expect(result.by, equals(const Offset(-3, 0)));
    });

    test('takes the nearest line, and none beyond reach', () {
      // Down to the top of the second (+4); the first is 7 away.
      final near = snapMove(const Rect.fromLTWH(0, 107, 10, 60), [
        const Rect.fromLTWH(50, 60, 10, 40),
        const Rect.fromLTWH(80, 111, 10, 100),
      ], reach: 6);
      expect(near.by.dy, equals(4));
      final far = snapMove(const Rect.fromLTWH(0, 120, 10, 10), [
        const Rect.fromLTWH(50, 100, 10, 10),
      ], reach: 6);
      expect(far.by, equals(Offset.zero));
      expect(far.guides, isEmpty);
    });

    test('takes a gap the row already has, and shows the equal gaps', () {
      // Two in a row 20 apart; the third comes after the second, 23 away.
      final result = snapMove(const Rect.fromLTWH(163, 0, 50, 50), [
        const Rect.fromLTWH(0, 0, 50, 50),
        const Rect.fromLTWH(70, 0, 70, 50),
      ], reach: 6);
      expect(result.by.dx, equals(-3));
      expect(result.gaps, hasLength(2));
      expect(result.gaps.map((gap) => gap.to - gap.from), everyElement(20));
    });

    test('goes to the grid where no element is in reach', () {
      final result = snapMove(
        const Rect.fromLTWH(33, 70, 10, 10),
        const [],
        reach: 6,
        grid: 24,
      );
      expect(result.by, equals(const Offset(-9, 2)));
    });

    test('an element in reach wins over the grid', () {
      final result = snapMove(
        const Rect.fromLTWH(33, 0, 10, 10),
        [const Rect.fromLTWH(35, 200, 10, 10)],
        reach: 6,
        grid: 24,
      );
      expect(result.by.dx, equals(2));
    });
  });

  group('a resized box', () {
    test('takes another height, and that one is marked', () {
      const other = Rect.fromLTWH(300, 500, 80, 120);
      final result = snapResize(const Rect.fromLTWH(0, 0, 100, 116), [
        other,
      ], reach: 6);
      expect(result.size, equals(const Size(100, 120)));
      expect(result.matched, contains(other));
    });

    test('snaps its right edge to another edge', () {
      final result = snapResize(const Rect.fromLTWH(0, 0, 97, 40), [
        const Rect.fromLTWH(100, 300, 50, 50),
      ], reach: 6);
      expect(result.size.width, equals(100));
      expect(result.guides.single.vertical, isTrue);
    });

    test('with a shape of its own, the other side follows', () {
      final result = snapResize(
        const Rect.fromLTWH(0, 0, 200, 98),
        [const Rect.fromLTWH(500, 500, 30, 100)],
        reach: 6,
        aspect: 2,
      );
      expect(result.size, equals(const Size(200, 100)));
    });

    test('with a shape of its own, kept above the smallest it may be', () {
      // Its right edge snaps to 62: half of that is below the smallest side.
      final result = snapResize(
        const Rect.fromLTWH(0, 0, 70, 35),
        [const Rect.fromLTWH(0, 200, 62, 10)],
        reach: 10,
        aspect: 2,
        minimum: 32,
      );
      expect(result.size, equals(const Size(64, 32)));
      // It no longer meets the edge it snapped to: no guide says it does.
      expect(result.guides, isEmpty);
      expect(result.matched, isEmpty);
    });
  });

  group('a group', () {
    final boxes = {
      'a': const Rect.fromLTWH(10, 0, 100, 50),
      'b': const Rect.fromLTWH(200, 30, 50, 100),
      'c': const Rect.fromLTWH(400, 10, 80, 80),
    };

    test('is aligned to its outermost edge or its middle', () {
      final left = alignBoxes(boxes, .left);
      expect(left.values.map((box) => box.left), everyElement(10));
      final top = alignBoxes(boxes, .top);
      expect(top.values.map((box) => box.top), everyElement(0));
      final middle = alignBoxes(boxes, .middle);
      expect(middle.values.map((box) => box.center.dy), everyElement(65));
    });

    test('is distributed with equal gaps, the first and last staying', () {
      final spread = distributeBoxes(boxes, horizontal: true);
      expect(spread['a']!.left, equals(10));
      expect(spread['c']!.right, equals(480));
      final first = spread['b']!.left - spread['a']!.right;
      final second = spread['c']!.left - spread['b']!.right;
      expect(first, closeTo(second, 0.001));
    });

    test('takes the largest height, a picture keeping its shape', () {
      final sized = sameSizeBoxes(
        boxes,
        width: false,
        height: true,
        aspects: {'a': 2},
      );
      expect(sized.values.map((box) => box.height), everyElement(100));
      expect(sized['a']!.width, equals(200));
      expect(sized['b']!.width, equals(50));
    });

    test('takes the size of the one covering most', () {
      final sized = sameSizeBoxes(boxes, width: true, height: true);
      expect(
        sized.values.map((box) => box.size),
        everyElement(const Size(80, 80)),
      );
    });
  });

  test('the grid rounds to its nearest line', () {
    expect(snapToGrid(37, 24), equals(48));
    expect(snapToGrid(11, 24), equals(0));
    expect(snapToGrid(-13, 24), equals(-24));
  });
}
