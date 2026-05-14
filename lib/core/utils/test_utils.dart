// // lib/core/utils/text_utils.dart
// import 'package:flutter/material.dart';

// extension SafeText on String {
//   Widget toSafeText({
//     TextStyle? style,
//     TextAlign textAlign = TextAlign.start,
//     int? maxLines,
//   }) {
//     return Text(
//       this,
//       style: style,
//       softWrap: true,
//       overflow: TextOverflow.visible,
//       maxLines: maxLines,
//       textAlign: textAlign,
//     );
//   }
// }

import 'package:flutter/material.dart';

extension SafeText on String {
  Widget toSafeText({
    TextStyle? style,
    TextAlign textAlign = TextAlign.start,
    int? maxLines,
    TextOverflow overflow = TextOverflow.visible,
    bool softWrap = true,
  }) {
    return Text(
      this,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}
