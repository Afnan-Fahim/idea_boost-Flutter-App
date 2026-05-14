import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double minHeight;
  final EdgeInsets padding;

  const AppButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.minHeight = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  }) : super(key: key);

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isDebouncing = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
            minimumSize: Size(double.infinity, widget.minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          onPressed:
              (widget.isLoading || _isDebouncing || widget.onPressed == null)
              ? null
              : () async {
                  if (_isDebouncing) return;
                  setState(() => _isDebouncing = true);

                  widget.onPressed?.call();

                  // Reset debounce after a short delay
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (mounted) {
                    setState(() => _isDebouncing = false);
                  }
                },
          child: (widget.isLoading || _isDebouncing)
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : AutoSizeText(
                  widget.text,
                  maxLines: 4,
                  minFontSize: 11,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
        ),
      ),
    );
  }
}
