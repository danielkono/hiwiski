import 'package:flutter/widgets.dart';

/// A tap that nothing else takes — on empty space, beside the text — closes the
/// keyboard.
///
/// On the phone Flutter keeps the focus on a tap outside the field, and a text of
/// several lines (a page, a description) has no "Done" key: the keyboard stayed and
/// could not be closed short of leaving the screen. Buttons, fields and rows claim
/// their taps first, so they work as before; only a tap that would have done nothing
/// closes it.
class TapAwayKeyboard extends StatelessWidget {
  const TapAwayKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: .translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}
