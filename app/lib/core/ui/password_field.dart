import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_symbols.dart';

/// A password field with an eye toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.autofocus = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  final String? errorText;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          icon: Icon(
            _hidden ? HiwiskiSymbols.visibility : HiwiskiSymbols.visibilityOff,
          ),
          onPressed: () => setState(() => _hidden = !_hidden),
          tooltip: _hidden ? l.loginShowPassword : l.loginHidePassword,
        ),
      ),
    );
  }
}
