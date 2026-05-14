// lib/core/utils/perf_utils.dart
import 'package:flutter/material.dart';

/// 🚀 PERF: Performance monitoring utility for debugging frame skips
class PerfUtils {
  static void logFrameSkip(String screenName, int skippedFrames) {
    debugPrint(
      '⚠️ PERF: $screenName skipped $skippedFrames frames - check CPU usage',
    );
  }

  /// 🚀 PERF: Defer non-critical tasks to after first frame render
  static void deferAfterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }

  /// 🚀 PERF: Schedule microtask for low-priority operations
  static void scheduleMicrotask(VoidCallback callback) {
    Future.microtask(callback);
  }
}
