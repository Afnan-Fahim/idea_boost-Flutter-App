import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Enhanced service for profile image handling with optimization and background upload
class ProfileImageService {
  static const String _prefix = 'profile_photo_';
  static const String _tempPrefix = 'temp_profile_';

  /// Save temporary local image for instant preview
  static Future<void> saveTempLocalImage(String uid, String imagePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_tempPrefix$uid', imagePath);
    } catch (_) {
      // ignore errors silently
    }
  }

  /// Get temporary local image path
  static Future<String?> getTempLocalImage(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_tempPrefix$uid');
    } catch (_) {
      return null;
    }
  }

  /// Clear temporary local image
  static Future<void> clearTempLocalImage(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_tempPrefix$uid');
    } catch (_) {
      // ignore
    }
  }

  /// Compress image for faster upload with fallback
  static Future<Uint8List?> compressImage(String imagePath) async {
    try {
      debugPrint('🔄 Starting image compression for: $imagePath');

      // Check if file exists
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('❌ File does not exist: $imagePath');
        return null;
      }

      // Try compression first
      final result = await FlutterImageCompress.compressWithFile(
        imagePath,
        quality: 75,
        minWidth: 300,
        minHeight: 300,
        format: CompressFormat.jpeg,
      );

      if (result != null) {
        debugPrint('✅ Image compressed: ${result.length} bytes');
        return result;
      } else {
        debugPrint('⚠️ Compression failed, using original file');
        // Fallback: read original file
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('⚠️ Compression error: $e, using original file');
      try {
        // Fallback: read original file
        final file = File(imagePath);
        return await file.readAsBytes();
      } catch (fallbackError) {
        debugPrint('❌ Fallback read error: $fallbackError');
        return null;
      }
    }
  }

  /// Upload image file directly (fallback method)
  static Future<String?> uploadImageFile({
    required String userId,
    required String imagePath,
    Function(double)? onProgress,
  }) async {
    try {
      debugPrint('🚀 Direct file upload for user: $userId');

      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('❌ File does not exist: $imagePath');
        return null;
      }

      final storageRef = FirebaseStorage.instance.ref().child(
        'users/$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final uploadTask = storageRef.putFile(
        file,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'originalUpload': 'true',
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      // Track upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
        debugPrint(
          '📤 Direct upload progress: ${(progress * 100).toStringAsFixed(1)}%',
        );
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('✅ Direct upload completed: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('❌ Direct upload error: $e');
      debugPrint('❌ Upload details - userId: $userId, imagePath: $imagePath');
      return null;
    }
  }

  /// Upload compressed image to Firebase Storage with progress tracking
  static Future<String?> uploadCompressedImage({
    required String userId,
    required Uint8List imageData,
    Function(double)? onProgress,
  }) async {
    try {
      debugPrint(
        '🚀 Starting upload for user: $userId (${imageData.length} bytes)',
      );

      final storageRef = FirebaseStorage.instance.ref().child(
        'users/$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final uploadTask = storageRef.putData(
        imageData,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'compressed': 'true',
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      // Track upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
        debugPrint(
          '📤 Upload progress: ${(progress * 100).toStringAsFixed(1)}%',
        );
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('✅ Upload completed: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      return null;
    }
  }

  /// Update user profile in Firestore
  static Future<bool> updateUserProfile(String userId, String imageUrl) async {
    try {
      debugPrint('📝 Updating Firestore profile for: $userId');

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'photoUrl': imageUrl,
      });

      debugPrint('✅ Firestore updated successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Firestore update error: $e');
      return false;
    }
  }

  static Future<void> saveLocalProfileUrl(String uid, String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$uid', url);
      // Clear temp image when permanent URL is saved
      await clearTempLocalImage(uid);
    } catch (_) {
      // ignore errors silently - caching is best-effort
    }
  }

  static Future<String?> getLocalProfileUrl(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_prefix$uid');
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteLocalProfileUrl(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$uid');
      await clearTempLocalImage(uid);
    } catch (_) {
      // ignore
    }
  }
}
