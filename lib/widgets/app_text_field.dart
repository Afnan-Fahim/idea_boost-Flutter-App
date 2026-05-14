import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  final String hintText;
  final int maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final EdgeInsets contentPadding;

  const AppTextField({
    Key? key,
    required this.hintText,
    this.maxLines = 1,
    this.minLines = 1,
    this.onChanged,
    this.controller,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: minLines,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.grey[300] ?? Colors.grey,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
        ),
        contentPadding: contentPadding,
        isDense: false,
      ),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
  }
}
