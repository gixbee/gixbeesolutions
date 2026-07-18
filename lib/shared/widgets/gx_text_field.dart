import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';

/// Gixbee 2026 design language — the shared glass text input.
///
/// Completes the `gx_*` family (button/dialog/sheet/snackbar/empty/calendar/
/// time-picker) with a single v106 input so screens stop hand-rolling either a
/// [GlassContainer] + `TextFormField(border: InputBorder.none)` or a stock
/// Material `TextFormField(labelText:, prefixIcon:)` (which inherits the global
/// orange theme and breaks the dark-glass look).
///
/// Visuals: an optional caption [label] above a translucent glass field
/// (light [BackdropFilter] blur + faint fill + 1px border). The border + cursor
/// animate to [accent] on focus — defaults to [GixbeeTheme.accentPurple] but
/// every screen can pass its quad colour (business=accentBlue, find-job=
/// accentGreen, …) exactly like [GxButton].
///
/// It is a [FormField]-compatible [TextFormField] under the hood, so [validator]
/// works inside a [Form]; all the common passthroughs are exposed. Dependency-free.
class GxTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Caption rendered above the field. Null → no label row.
  final String? label;
  final String? hint;

  final IconData? prefixIcon;

  /// Trailing widget (e.g. a visibility toggle or a unit chip). Takes
  /// precedence over [suffixIcon].
  final Widget? suffix;
  final IconData? suffixIcon;

  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  final int maxLines;
  final int? minLines;
  final int? maxLength;

  final bool enabled;
  final bool autofocus;
  final bool readOnly;

  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final VoidCallback? onTap;

  /// Focus-ring + cursor colour. Null → theme shell [GxColors.accent].
  final Color? accent;

  const GxTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.readOnly = false,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.accent,
  });

  @override
  State<GxTextField> createState() => _GxTextFieldState();
}

class _GxTextFieldState extends State<GxTextField> {
  late FocusNode _node;
  bool _ownsNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode();
      _ownsNode = true;
    }
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_node.hasFocus != _focused) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? context.gx.accent;
    final Color borderColor = _focused
        ? accent.withValues(alpha: 0.6)
        : context.gx.ink.withValues(alpha: 0.08);

    Widget? suffixWidget = widget.suffix;
    if (suffixWidget == null && widget.suffixIcon != null) {
      suffixWidget = Icon(
        widget.suffixIcon,
        color: context.gx.ink.withValues(alpha: 0.45),
        size: 20,
      );
    }

    final field = TextFormField(
      controller: widget.controller,
      focusNode: _node,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      cursorColor: accent,
      style: TextStyle(color: context.gx.ink, fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(color: context.gx.ink.withValues(alpha: 0.30)),
        prefixIcon: widget.prefixIcon != null
            ? Icon(
                widget.prefixIcon,
                color: _focused
                    ? accent
                    : context.gx.ink.withValues(alpha: 0.45),
                size: 20,
              )
            : null,
        suffixIcon: suffixWidget,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        counterText: '',
        errorStyle: const TextStyle(
          color: GixbeeTheme.brandRed,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );

    final glass = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: context.gx.ink.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: field,
        ),
      ),
    );

    if (widget.label == null) return glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            widget.label!,
            style: TextStyle(
              color: context.gx.ink.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        glass,
      ],
    );
  }
}
