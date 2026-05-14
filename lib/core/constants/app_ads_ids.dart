import 'dart:io';

class AppAdsIds {
  // Banner Ad Unit
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-1701146063267014/8664605418'; // Android
    } else if (Platform.isIOS) {
      return 'YOUR_IOS_BANNER_UNIT_ID'; // Replace with your iOS banner ID
    }
    return '';
  }

  // App ID
  static String get appId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-1701146063267014~6732576642';
    } else if (Platform.isIOS) {
      return 'YOUR_IOS_APP_ID';
    }
    return '';
  }
}
