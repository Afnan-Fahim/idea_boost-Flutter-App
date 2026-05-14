import 'package:flutter/material.dart';
/// Fallback AppStyles definitions to ensure this file compiles even if the
/// project's styles.dart does not define AppStyles; adjust values as needed.
class AppStyles {
  static const TextStyle logoTextStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );

  static const TextStyle subtitleTextStyle = TextStyle(
    fontSize: 16,
    color: Colors.black54,
  );

  static const TextStyle bodyTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.black87,
  );

  static const TextStyle headingTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );

  static const TextStyle titleTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );
}
