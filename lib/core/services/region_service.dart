import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Service to collect region data for ANTI-VPN tier resolution
class RegionService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Get device locale country code
  /// Returns country code like "US", "GB", "IN"
  /// Safely parses locale string like "en_US" or "en-US" → "US"
  String _parseCountryFromLocale(String locale) {
    final parts = locale.split(RegExp(r'[_-]'));
    // Find the 2-letter country code part (uppercase)
    return parts.lastWhere(
      (p) => p.length == 2 && p == p.toUpperCase(),
      orElse: () => parts.last,
    );
  }

  Future<String?> getDeviceLocale() async {
    try {
      if (Platform.isAndroid) {
        await _deviceInfo.androidInfo;
        return _parseCountryFromLocale(Platform.localeName);
      } else if (Platform.isIOS) {
        await _deviceInfo.iosInfo;
        return _parseCountryFromLocale(Platform.localeName);
      }
      // Fallback to platform locale
      return _parseCountryFromLocale(Platform.localeName);
    } catch (e) {
      debugPrint('❌ Failed to get device locale: $e');
      return null;
    }
  }

  /// Get store country (App Store or Play Store)
  /// Strategy: Try platform-specific store detection, fallback to device locale
  /// - Production (from store): Attempts to detect actual store country
  /// - Development (flutter run): Uses device locale
  Future<String?> getStoreCountry() async {
    try {
      String? storeCountry;

      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;

        // Try to detect if app is from Play Store
        // Method 1: Check installer package name (requires platform channel)
        // Method 2: Use SIM country if available (requires permissions)
        // For MVP: Use device locale with indicator if it's from store

        storeCountry = await _tryGetAndroidStoreCountry(androidInfo);
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;

        // iOS: In production, StoreKit can provide storefront.countryCode
        // For MVP: Use device locale (iOS users rarely change this)

        storeCountry = await _tryGetIOSStoreCountry(iosInfo);
      }

      // Fallback to device locale
      if (storeCountry == null || storeCountry.isEmpty) {
        storeCountry = _parseCountryFromLocale(Platform.localeName);
        debugPrint('📱 Using device locale for store country: $storeCountry');
      }

      return storeCountry;
    } catch (e) {
      debugPrint('❌ Failed to get store country: $e');
      // Final fallback
      return _parseCountryFromLocale(Platform.localeName);
    }
  }

  /// Try to get Android Play Store country
  /// Returns null if detection fails (falls back to locale)
  Future<String?> _tryGetAndroidStoreCountry(dynamic androidInfo) async {
    try {
      // Check if this is a physical device (not emulator)
      if (androidInfo.isPhysicalDevice) {
        // On real devices with SIM, we could get country from telephony
        // For MVP without additional permissions, we return null to use locale
        // Future enhancement: Add platform channel to call:
        // TelephonyManager.getSimCountryIso() or getNetworkCountryIso()
        debugPrint(
          '📱 Android device detected, using locale (store country N/A)',
        );
      } else {
        debugPrint('📱 Android emulator detected, using locale');
      }
      return null; // Use locale fallback
    } catch (e) {
      return null;
    }
  }

  /// Try to get iOS App Store country
  /// Returns null if detection fails (falls back to locale)
  Future<String?> _tryGetIOSStoreCountry(dynamic iosInfo) async {
    try {
      // On iOS, locale is generally reliable as it reflects App Store region
      // Advanced: Could use StoreKit SKPaymentQueue.storefront (requires native code)
      if (iosInfo.isPhysicalDevice) {
        debugPrint('📱 iOS device detected, using locale (store country N/A)');
      } else {
        debugPrint('📱 iOS simulator detected, using locale');
      }
      return null; // Use locale fallback
    } catch (e) {
      return null;
    }
  }

  /// Get IP-based country code (ANTI-VPN)
  /// Uses multiple IP geolocation services with fallback
  /// Returns country code like "US", "GB", "PK"
  Future<String?> getIpCountry() async {
    // Try primary service: ipapi.co
    try {
      debugPrint('🌐 Attempting IP detection via ipapi.co...');
      final response = await http
          .get(Uri.parse('https://ipapi.co/country/'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final countryCode = response.body.trim();
        if (countryCode.isNotEmpty && countryCode.length == 2) {
          debugPrint('✅ IP Country detected (ipapi.co): $countryCode');
          return countryCode.toUpperCase();
        }
      }
      debugPrint('⚠️ ipapi.co returned invalid data: ${response.body}');
    } catch (e) {
      debugPrint('⚠️ ipapi.co failed: $e');
    }

    // Try fallback service: ip-api.com
    try {
      debugPrint('🌐 Attempting IP detection via ip-api.com...');
      final response = await http
          .get(Uri.parse('https://ip-api.com/json/?fields=countryCode'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final countryCode = data['countryCode'] as String?;
        if (countryCode != null && countryCode.isNotEmpty) {
          debugPrint('✅ IP Country detected (ip-api.com): $countryCode');
          return countryCode.toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('⚠️ ip-api.com failed: $e');
    }

    debugPrint('❌ All IP detection services failed');
    return null;
  }

  /// Generate device fingerprint for trial protection
  /// Combines device identifiers to create unique fingerprint
  Future<String> getDeviceFingerprint() async {
    try {
      String fingerprint = '';

      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;

        fingerprint =
            '${androidInfo.id}_${androidInfo.model}_${androidInfo.device}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;

        fingerprint =
            '${iosInfo.identifierForVendor}_${iosInfo.model}_${iosInfo.systemVersion}';
      }

      // Hash the fingerprint for privacy using SHA-256 (stable across all app restarts)
      final bytes = utf8.encode(fingerprint);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      debugPrint('❌ Failed to generate device fingerprint: $e');
      // Fallback: use a fixed error string hash (not timestamp, which changes every run)
      return sha256.convert(utf8.encode('fallback_fingerprint')).toString();
    }
  }

  /// Collect all region data for user initialization
  /// Returns map with deviceLocale, storeCountry, ipCountry, deviceFingerprint
  /// Implements ANTI-VPN tier resolution per spec section 1.1
  Future<Map<String, String?>> collectRegionData() async {
    final deviceLocale = await getDeviceLocale();
    final storeCountry = await getStoreCountry();
    final ipCountry = await getIpCountry();
    final deviceFingerprint = await getDeviceFingerprint();

    debugPrint('🌍 Region data collected (ANTI-VPN):');
    debugPrint('  - Device Locale: $deviceLocale');
    debugPrint('  - Store Country: $storeCountry');
    debugPrint('  - IP Country: $ipCountry');
    debugPrint(
      '  - Device Fingerprint: ${deviceFingerprint.length > 10 ? deviceFingerprint.substring(0, 10) : deviceFingerprint}...',
    );

    return {
      'deviceLocale': deviceLocale,
      'storeCountry': storeCountry,
      'ipCountry': ipCountry,
      'deviceFingerprint': deviceFingerprint,
    };
  }
}
