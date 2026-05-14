// // NEW FILE - Helper utilities for responsive UI

// // lib/core/utils/responsive_helper.dart

// import 'package:flutter/material.dart';

// class ResponsiveHelper {
//   static bool isMobile(BuildContext context) =>
//       MediaQuery.of(context).size.width < 600;

//   static bool isTablet(BuildContext context) =>
//       MediaQuery.of(context).size.width >= 600 &&
//       MediaQuery.of(context).size.width < 1200;

//   static bool isDesktop(BuildContext context) =>
//       MediaQuery.of(context).size.width >= 1200;

//   static double getWidth(BuildContext context) =>
//       MediaQuery.of(context).size.width;

//   static double getHeight(BuildContext context) =>
//       MediaQuery.of(context).size.height;

//   static double getMaxWidth(BuildContext context) {
//     final width = getWidth(context);
//     if (width > 1200) return 1200;
//     if (width > 800) return width * 0.9;
//     return width * 0.95;
//   }

//   /// Responsive font size: scales based on screen width
//   static double responsiveFontSize(
//     BuildContext context, {
//     required double mobileSize,
//     double? tabletSize,
//     double? desktopSize,
//   }) {
//     final width = getWidth(context);
//     if (width >= 1200) return desktopSize ?? mobileSize * 1.2;
//     if (width >= 600) return tabletSize ?? mobileSize * 1.1;
//     return mobileSize;
//   }

//   /// Responsive padding: scales based on screen width
//   static EdgeInsets responsivePadding(
//     BuildContext context, {
//     required double mobilePadding,
//     double? tabletPadding,
//     double? desktopPadding,
//   }) {
//     final width = getWidth(context);
//     double padding = mobilePadding;
//     if (width >= 1200) padding = desktopPadding ?? mobilePadding * 1.5;
//     if (width >= 600) padding = tabletPadding ?? mobilePadding * 1.2;
//     return EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.75);
//   }

//   /// Text overflow handling: ellipsis for long text
//   static TextOverflow getTextOverflow() => TextOverflow.visible;

//   /// Max lines for responsive text
//   static int getMaxLines(BuildContext context, {int mobileLines = 2}) {
//     if (isDesktop(context)) return mobileLines + 2;
//     if (isTablet(context)) return mobileLines + 1;
//     return mobileLines;
//   }
// }

import 'package:flutter/material.dart';

class ResponsiveHelper {
  static double _width(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double _height(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static bool isMobile(BuildContext context) => _width(context) < 600;

  static bool isTablet(BuildContext context) =>
      _width(context) >= 600 && _width(context) < 1200;

  static bool isDesktop(BuildContext context) => _width(context) >= 1200;

  static double getWidth(BuildContext context) => _width(context);

  static double getHeight(BuildContext context) => _height(context);

  static double getMaxWidth(BuildContext context) {
    final width = _width(context);
    if (width >= 1200) return 1200;
    if (width >= 800) return width * 0.9;
    return width * 0.95;
  }

  /// Responsive font size
  static double responsiveFontSize(
    BuildContext context, {
    required double mobileSize,
    double? tabletSize,
    double? desktopSize,
  }) {
    final width = _width(context);

    if (width >= 1200) return desktopSize ?? mobileSize * 1.25;
    if (width >= 600) return tabletSize ?? mobileSize * 1.1;
    return mobileSize;
  }

  /// Responsive padding
  static EdgeInsets responsivePadding(
    BuildContext context, {
    required double mobilePadding,
    double? tabletPadding,
    double? desktopPadding,
  }) {
    final width = _width(context);

    double horizontal = mobilePadding;
    if (width >= 1200) {
      horizontal = desktopPadding ?? mobilePadding * 1.6;
    } else if (width >= 600) {
      horizontal = tabletPadding ?? mobilePadding * 1.25;
    }

    return EdgeInsets.symmetric(
      horizontal: horizontal,
      vertical: horizontal * 0.75,
    );
  }

  static TextOverflow getTextOverflow() => TextOverflow.visible;

  static int getMaxLines(BuildContext context, {int mobileLines = 2}) {
    if (isDesktop(context)) return mobileLines + 2;
    if (isTablet(context)) return mobileLines + 1;
    return mobileLines;
  }
}
