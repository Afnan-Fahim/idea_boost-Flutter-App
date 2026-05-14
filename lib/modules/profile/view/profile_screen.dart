import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'dart:async';
import '../../../core/constants/locale_config.dart';
import '../../../core/services/admob_service.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../../core/utils/helpers.dart';
import '../../../data/models/user_model.dart';
import '../../../data/notifiers/user_notifier.dart';
import '../../../data/repository/auth_repository.dart';
import '../../../core/services/user_service.dart';
import '../../../core/services/profile_image_service.dart';
import '../../../core/services/reward_service.dart';
import '../../../core/services/stale_data_detector.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  late final TextEditingController _nameController;
  final AdMobService adMobService = AdMobService();
  String? _tempImagePath;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();

    // Show all saved tokens when profile screen opens
    RewardService().getStoredTokens();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fade = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slide = Tween(
      begin: 100.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });

    // Load banner ad
    adMobService.loadBanner(onLoaded: () => mounted ? setState(() {}) : null);
  }

  ImageProvider? _buildImageProvider(UserModel user) {
    // 1. PRIORITY: Show temp image for instant preview
    if (_tempImagePath != null && _tempImagePath!.isNotEmpty) {
      return FileImage(File(_tempImagePath!));
    }

    // 2. FALLBACK: Show permanent photo URL
    final photo = user.photoUrl;
    if (photo != null && photo.isNotEmpty) {
      if (photo.startsWith('assets/')) return AssetImage(photo);
      if (photo.startsWith('http') || photo.startsWith('https')) {
        return NetworkImage(photo);
      }
    }

    // 3. Return null if no avatar is set
    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    adMobService.disposeBanner();
    super.dispose();
  }

  // Photo upload functionality - restored to original working version
  Future<void> _pickAndUploadPhoto(UserModel user) async {
    try {
      final startTime = DateTime.now();
      debugPrint('⏱️ [START] Profile image upload process started');

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      if (!mounted) return;

      // 1. INSTANT PREVIEW: Show selected image immediately
      setState(() {
        _tempImagePath = image.path;
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      // Show instant preview message
      showSnackBarSafe(
        context,
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.visibility, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: AutoSizeText(
                  'profile.photo_preview_loaded'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      // 2. BACKGROUND UPLOAD: Compress and upload to Firebase
      setState(() {
        _uploadProgress = 0.1; // Show slight progress for compression
      });

      // Compress image before upload
      final compressionStart = DateTime.now();
      debugPrint('🔄 [COMPRESSION] Starting image compression...');
      final compressedBytes = await ProfileImageService.compressImage(
        image.path,
      );

      if (compressedBytes == null) {
        throw Exception('errors.image_compression_failed'.tr());
      }

      final compressionTime = DateTime.now().difference(compressionStart);
      debugPrint(
        '✅ [COMPRESSION] Completed in ${compressionTime.inSeconds}.${compressionTime.inMilliseconds % 1000}s',
      );
      debugPrint('   Size: ${compressedBytes.length} bytes');

      final storageRef = FirebaseStorage.instance.ref().child(
        'users/${user.id}/profile.jpg',
      );

      final uploadStart = DateTime.now();
      debugPrint('🚀 [UPLOAD] Starting Firebase Storage upload...');

      final uploadTask = storageRef.putData(
        compressedBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Track upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        if (mounted) {
          setState(() {
            _uploadProgress = progress;
          });
        }
        debugPrint(
          '📤 Upload progress: ${(progress * 100).toStringAsFixed(1)}%',
        );
      });

      // Wait for upload to complete
      final snapshot = await uploadTask;
      final uploadTime = DateTime.now().difference(uploadStart);
      debugPrint(
        '✅ [UPLOAD] Completed in ${uploadTime.inSeconds}.${uploadTime.inMilliseconds % 1000}s',
      );

      final downloadUrlStart = DateTime.now();
      final downloadUrl = await snapshot.ref.getDownloadURL();
      final downloadUrlTime = DateTime.now().difference(downloadUrlStart);
      debugPrint(
        '✅ [URL] Retrieved download URL in ${downloadUrlTime.inSeconds}.${downloadUrlTime.inMilliseconds % 1000}s',
      );

      debugPrint('🔍 Profile Upload: downloadUrl = $downloadUrl');
      debugPrint('🔍 Profile Upload: user.id = ${user.id}');

      // Update Firestore
      final firestoreStart = DateTime.now();
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'photoUrl': downloadUrl,
      });
      final firestoreTime = DateTime.now().difference(firestoreStart);
      debugPrint(
        '✅ [FIRESTORE] Updated in ${firestoreTime.inSeconds}.${firestoreTime.inMilliseconds % 1000}s',
      );

      debugPrint('✅ Profile Upload: Firestore updated successfully');

      // Cache locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_photo_${user.id}', downloadUrl);

      debugPrint('✅ Profile Upload: Local cache updated');

      final totalTime = DateTime.now().difference(startTime);
      debugPrint(
        '🏁 [TOTAL] Complete process finished in ${totalTime.inSeconds}.${totalTime.inMilliseconds % 1000}s',
      );

      if (!mounted) return;

      // Clear temp image after a delay to let new image load smoothly
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      setState(() {
        _isUploading = false;
        _tempImagePath = null; // Now clear temp image
      });

      // Show success message
      showSnackBarSafe(
        context,
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_done, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: AutoSizeText(
                  'photo_synced'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('❌ Profile upload failed: $e');

      if (!mounted) return;

      setState(() {
        _isUploading = false;
        _tempImagePath = null;
      });

      showSnackBarSafe(
        context,
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: AutoSizeText(
                  'profile.photo_upload_failed'.tr(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserNotifier>().userModel;
    final isMobile = ResponsiveHelper.isMobile(context);

    if (user.email.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, isMobile),
      body: _buildBody(context, user, isMobile),
      bottomNavigationBar: (!user.isPro && adMobService.isBannerLoaded)
          ? SafeArea(
              child: Container(
                color: Colors.white,
                child: SizedBox(
                  height: adMobService.bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: adMobService.bannerAd!),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ------------------ UI BUILDERS ------------------

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isMobile) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color.fromARGB(255, 53, 53, 53).withOpacity(0.5),
              Colors.transparent,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12),
        child: Center(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
      // 🎨 No title - pure glassmorphic app bar
      title: const SizedBox.shrink(),
      centerTitle: true,
      actions: [
        // Delete Account Button
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: _buildAppBarDeleteButton(context),
        ),
        // Logout Button
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 16),
          child: _buildAppBarLogoutButton(context),
        ),
      ],
    );
  }

  // 🚀 Delete button for app bar (premium style)
  Widget _buildAppBarDeleteButton(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade400, Colors.red.shade600],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDeleteAccountDialog(context),
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  // 🚀 Logout button for app bar (premium cyan theme)
  Widget _buildAppBarLogoutButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showLogoutDialog(context),
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.logout_rounded, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, UserModel user, bool isMobile) {
    return Container(
      constraints: BoxConstraints.expand(
        height: MediaQuery.of(context).size.height,
      ),
      // 🎨 Premium gradient: dark + cyan theme mix
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0F0F1E),
            const Color(0xFF1A2a3a),
            const Color(0xFF0a1a2e).withOpacity(0.95),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 24,
            vertical: 20,
          ),
          child: Column(
            children: [
              _buildAvatar(user, isMobile),
              const SizedBox(height: 16),
              _buildHeader(user, isMobile),
              const SizedBox(height: 24),
              _buildAccountSection(context, user, isMobile),
              const SizedBox(height: 20),
              _buildUsageCard(user, isMobile),
              const SizedBox(height: 20),
              if (user.isPro && user.regionTier == 'tier1') ...[
                _buildProWelcomeCard(isMobile),
                const SizedBox(height: 20),
              ] else if (!user.isPro) ...[
                _buildAdRewardsCard(user, isMobile),
                const SizedBox(height: 16),
                if (user.regionTier == 'tier1')
                  _buildPremiumUpgradeCard(isMobile)
                else
                  _buildHowToEarnCard(user, isMobile),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(UserModel user, bool isMobile) {
    final imageProvider = _buildImageProvider(user);

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, _slide.value),
            child: GestureDetector(
              onTap: _isUploading ? null : () => _pickAndUploadPhoto(user),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Outer glow ring
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: user.isPro
                            ? [const Color(0xFFFFED4B), const Color(0xFFFAD94D)]
                            : [
                                const Color(0xFF00D4FF),
                                const Color(0xFF0099FF),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (user.isPro
                                      ? const Color(0xFFFFED4B)
                                      : const Color(0xFF00D4FF))
                                  .withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1A1A2E),
                      ),
                      child: CircleAvatar(
                        radius: isMobile ? 52 : 64,
                        backgroundColor: imageProvider != null
                            ? Colors.grey[800]
                            : const Color(0xFF2A2A4E),
                        backgroundImage: imageProvider,
                        child: imageProvider == null
                            ? Icon(
                                Icons.person_rounded,
                                size: isMobile ? 52 : 64,
                                color: Colors.white38,
                              )
                            : null,
                      ),
                    ),
                  ),

                  // Lightweight progress bar at bottom (non-blocking preview)
                  if (_isUploading && !_isLoggingOut)
                    Positioned(
                      bottom: 8,
                      left: 12,
                      right: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 3,
                          child: LinearProgressIndicator(
                            value: _uploadProgress,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _uploadProgress >= 1.0
                                  ? Colors.green
                                  : const Color(0xFF00D4FF),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Camera icon (bottom-right)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isUploading
                              ? [Colors.orange, Colors.deepOrange]
                              : _tempImagePath != null
                              ? [Colors.blue, Colors.blueAccent]
                              : [
                                  const Color(0xFF00D4FF),
                                  const Color(0xFF0099FF),
                                ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1A1A2E),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _isUploading
                            ? Icons.cloud_upload_rounded
                            : _tempImagePath != null
                            ? Icons.sync_rounded
                            : Icons.camera_alt_rounded,
                        size: isMobile ? 14 : 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Status badge (top-left) - FREE/PRO
                  Positioned(
                    top: -4,
                    left: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: user.isPro
                              ? [
                                  const Color(0xFFFFED4B),
                                  const Color(0xFFFAD94D),
                                ]
                              : [
                                  const Color(0xFF4A4A6A),
                                  const Color(0xFF3A3A5A),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF1A1A2E),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (user.isPro
                                        ? const Color(0xFFFFED4B)
                                        : Colors.black)
                                    .withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            user.isPro
                                ? Icons.star_rounded
                                : Icons.person_outline_rounded,
                            size: 10,
                            color: user.isPro
                                ? const Color(0xFF1A1A2E)
                                : Colors.white70,
                          ),
                          const SizedBox(width: 3),
                          AutoSizeText(
                            user.isPro
                                ? 'profile.plan_pro'.tr()
                                : 'profile.plan_free'.tr(),
                            style: TextStyle(
                              color: user.isPro
                                  ? const Color(0xFF1A1A2E)
                                  : Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Preview indicator (syncing)
                  if (_tempImagePath != null && !_isUploading)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF1A1A2E),
                            width: 1.5,
                          ),
                        ),
                        child: const AutoSizeText(
                          'Syncing',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(UserModel user, bool isMobile) {
    return Column(
      children: [
        AutoSizeText(
          user.name,
          style: TextStyle(
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AutoSizeText(
            user.email,
            style: TextStyle(
              fontSize: isMobile ? 12 : 13,
              color: Colors.white54,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection(
    BuildContext context,
    UserModel user,
    bool isMobile,
  ) {
    return Column(
      children: [
        _buildGlassField(
          icon: Icons.person_outline_rounded,
          title: 'profile.display_name_title'.tr(),
          value: user.name,
          isMobile: isMobile,
          onTap: () => _showNameDialog(context),
        ),
        const SizedBox(height: 8),
        // _buildGlassField(
        //   icon: Icons.mail_outline_rounded,
        //   title: 'profile.account_email_title'.tr(),
        //   value: user.email,
        //   isMobile: isMobile,
        //   isEditable: false,
        // ),
        const SizedBox(height: 8),
        _buildGlassField(
          icon: Icons.language_rounded,
          title: 'profile.app_language_title'.tr(),
          value: context.locale.languageCode.toUpperCase(),
          isMobile: isMobile,
          onTap: () {
            if (!mounted) return;
            _showLanguageDialog(context);
          },
        ),
      ],
    );
  }

  // ------------------ ACTIONS ------------------

  Future<void> _updateUserField(String field, dynamic value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      field: value,
    }, SetOptions(merge: true));
  }

  void _showNameDialog(BuildContext context) {
    _nameController.text = context.read<UserNotifier>().userModel.name;
    const accent = Color(0xFF00D4FF);

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E).withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.15),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AutoSizeText(
                  'profile.change_name_dialog_title'.tr(),
                  maxLines: 3,
                  minFontSize: 12,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: accent.withOpacity(0.25)),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                          child: AutoSizeText(
                            'general.cancel'.tr(),
                            maxLines: 1,
                            minFontSize: 11,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            foregroundColor: const Color(0xFF0B1220),
                            backgroundColor: accent,
                            disabledForegroundColor: Colors.white54,
                            disabledBackgroundColor: Colors.white24,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            final name = _nameController.text.trim();
                            if (name.isNotEmpty) {
                              await _updateUserField('name', name);
                              if (mounted) Navigator.pop(dialogContext);
                            }
                          },
                          child: AutoSizeText(
                            'general.save'.tr(),
                            maxLines: 1,
                            minFontSize: 11,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    // 🚀 PERF: Pre-compute once, not per-build
    final langs = supportedLangCodes;
    final names = activeLangNames;
    final currentCode = context.locale.languageCode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final screenHeight = MediaQuery.of(sheetContext).size.height;
        final screenWidth = MediaQuery.of(sheetContext).size.width;
        final isMobile = screenWidth < 600;

        return Container(
          height:
              screenHeight * (isMobile ? 0.75 : 0.65) -
              MediaQuery.of(sheetContext).viewPadding.bottom,
          decoration: const BoxDecoration(
            color: Color(0xFF0F0F1E),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
          child: Column(
            children: [
              // ── Drag Handle (subtle) ──
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: 28,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),

              // ── Header ──
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 24 : 32,
                  isMobile ? 16 : 20,
                  isMobile ? 24 : 32,
                  isMobile ? 12 : 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'profile.select_language_title'.tr(),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: isMobile ? 18 : 20,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Subtle separator ──
              Divider(
                color: Colors.white.withOpacity(0.06),
                height: 1,
                thickness: 0.8,
                indent: 0,
                endIndent: 0,
              ),

              // ── Language List ──
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 24,
                    isMobile ? 8 : 10,
                    isMobile ? 16 : 24,
                    (isMobile ? 24 : 30) +
                        MediaQuery.of(sheetContext).viewPadding.bottom,
                  ),
                  itemCount: langs.length,
                  itemBuilder: (context, index) {
                    final code = langs[index];
                    final isSelected = code == currentCode;
                    final name = names[code] ?? code.toUpperCase();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            if (code == currentCode) return;
                            context.setLocale(Locale(code));
                            final platformLocale = Platform.localeName;
                            final platformCountry =
                                platformLocale.split(RegExp(r'[_-]')).length > 1
                                ? platformLocale
                                      .split(RegExp(r'[_-]'))
                                      .last
                                      .toUpperCase()
                                : code.toUpperCase();
                            final fullLocaleTag = '$code-$platformCountry';
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            if (uid != null) {
                              FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .set({
                                    'language': code,
                                    'fullLocale': fullLocaleTag,
                                  }, SetOptions(merge: true));
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 12 : 16,
                              vertical: isMobile ? 10 : 11,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: isSelected
                                  ? const Color(0xFF1A3A52).withOpacity(0.6)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF00D4FF).withOpacity(0.25)
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: isMobile ? 10 : 12),

                                // ── Language Name ──
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.85),
                                      fontWeight: isSelected
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                      fontSize: isMobile ? 12 : 13,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ),

                                // ── Check Mark (only when selected) ──
                                if (isSelected)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6.0),
                                    child: Icon(
                                      Icons.check,
                                      color: const Color(0xFF00D4FF),
                                      size: isMobile ? 18 : 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    const accent = Color(0xFF00D4FF);
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E).withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.15),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AutoSizeText(
                  'profile.logout_confirm_title'.tr(),
                  maxLines: 2,
                  minFontSize: 12,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  'profile.logout_confirm_message'.tr(),
                  maxLines: 4,
                  minFontSize: 11,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: accent.withOpacity(0.25)),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                          child: AutoSizeText(
                            'general.cancel'.tr(),
                            maxLines: 1,
                            minFontSize: 11,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade500,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            // Close the logout dialog first
                            Navigator.pop(dialogContext);
                            setState(() => _isLoggingOut = true);

                            try {
                              // 1. Clear SharedPreferences
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.clear();
                              debugPrint('✅ SharedPreferences cleared');

                              // 2. Change locale
                              await context.setLocale(const Locale('en'));

                              // 3. Logout
                              await AuthRepository(UserService()).logout();

                              if (!mounted) return;

                              // 4. Navigate to login directly without progress dialog
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/login',
                                (_) => false,
                              );
                            } catch (e) {
                              debugPrint('❌ Logout error: $e');
                              if (!mounted) return;
                              setState(() => _isLoggingOut = false);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: AutoSizeText(
                                    'errors.action_failed'.tr(),
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: AutoSizeText(
                            'profile.logout'.tr(),
                            maxLines: 1,
                            minFontSize: 11,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------ REUSED UI ------------------

  Widget _buildGlassField({
    required IconData icon,
    required String title,
    required String value,
    required bool isMobile,
    bool isEditable = true,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isEditable ? onTap : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 14 : 18,
          vertical: isMobile ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF00D4FF), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    title,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: isMobile ? 11 : 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  AutoSizeText(
                    value,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: isMobile ? 14 : 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isEditable)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white38,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- Usage Card with new monetization logic ----
  // Calculate AI Generation Used for non-pro users (pure token-based)
  // Formula: used = totalGranted - totalRemaining
  //   Only counts non-expired tokens (expiresAt > now)
  //   totalGranted   = count(valid tokens) × aiPerRewardedAd
  //   totalRemaining = sum(aiUnlocksRemaining) from valid tokens
  Map<String, int> _calculateConsumedTokens(UserModel user) {
    if (user.activeRewardTokens == null || user.activeRewardTokens!.isEmpty) {
      return {'used': 0, 'total': 0};
    }

    final int aiPerAd = user.aiPerRewardedAd ?? 1;
    final now = DateTime.now();
    int tokenCount = 0;
    int totalRemaining = 0;

    user.activeRewardTokens!.forEach((tokenId, tokenData) {
      if (tokenData is Map<String, dynamic>) {
        // Skip expired tokens — they are stale from previous days
        final expiresAt = tokenData['expiresAt'];
        if (expiresAt != null) {
          DateTime? expiry;
          if (expiresAt is Timestamp) {
            expiry = expiresAt.toDate();
          } else if (expiresAt is DateTime) {
            expiry = expiresAt;
          }
          if (expiry != null && expiry.isBefore(now)) {
            return; // Skip this expired token
          }
        }

        tokenCount++;
        final aiUnlocks = tokenData['aiUnlocksRemaining'] as int? ?? 0;
        totalRemaining += aiUnlocks;
      }
    });

    final int totalGranted = tokenCount * aiPerAd;
    final int used = totalGranted - totalRemaining;

    return {'used': used, 'total': totalGranted};
  }

  Widget _buildUsageCard(UserModel user, bool isMobile) {
    return Selector<UserNotifier, UserModel>(
      selector: (_, notifier) => notifier.userModel,
      builder: (context, userModel, child) {
        final bool isPro = userModel.plan == 'pro';
        final int totalUsed =
            userModel.aiNanoUsedToday + userModel.aiMiniUsedToday;
        // PRO phased caps: 20 mini (Phase 1) + 80 nano (Phase 2) = 100 total
        final int totalEffectiveCap = 100;

        // Non-PRO: token-based formula (same as home_screen)
        final tokenStats = _calculateConsumedTokens(userModel);
        final int tokenUsed = tokenStats['used'] ?? 0;
        final int tokenTotal = tokenStats['total'] ?? 0;

        final double progress = isPro
            ? (totalUsed / totalEffectiveCap).clamp(0.0, 1.0)
            : (tokenTotal > 0 ? (tokenUsed / tokenTotal) : 0.0).clamp(0.0, 1.0);

        final bool isExceeded = isPro
            ? totalUsed >= totalEffectiveCap
            : tokenUsed >= tokenTotal && tokenTotal > 0;
        final bool isNearLimit = progress >= 0.7 && progress < 1.0;

        return Container(
          padding: EdgeInsets.all(isMobile ? 14 : 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isExceeded
                  ? [Colors.red.withOpacity(0.15), Colors.red.withOpacity(0.08)]
                  : [
                      const Color(0xFF1E3C72).withOpacity(0.8),
                      const Color(0xFF2A5298).withOpacity(0.6),
                    ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExceeded
                  ? Colors.redAccent.withOpacity(0.4)
                  : const Color(0xFF00D4FF).withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isExceeded
                    ? Colors.red.withOpacity(0.2)
                    : const Color(0xFF2A5298).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              /// HEADER
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isExceeded
                            ? [Colors.redAccent, Colors.red]
                            : const [Color(0xFF00D4FF), Color(0xFF0099FF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: isMobile ? 18 : 20,
                    ),
                  ),

                  SizedBox(width: isMobile ? 10 : 12),

                  /// TITLE + STATUS
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AutoSizeText(
                          'profile.daily_generations_title'.tr(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 13 : 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (!isPro)
                          AutoSizeText(
                            isExceeded
                                ? 'profile.limit_reached'.tr()
                                : 'profile.remaining'.tr(),
                            style: TextStyle(
                              color: isExceeded
                                  ? Colors.redAccent
                                  : Colors.white54,
                              fontSize: isMobile ? 11 : 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  /// COUNTER (Only for non-PRO)
                  if (!isPro)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 10 : 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isExceeded
                            ? Colors.redAccent.withOpacity(0.2)
                            : isNearLimit
                            ? Colors.orange.withOpacity(0.2)
                            : const Color(0xFF00D4FF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: AutoSizeText(
                        '$tokenUsed / $tokenTotal',
                        style: TextStyle(
                          color: isExceeded
                              ? Colors.redAccent
                              : isNearLimit
                              ? Colors.orange
                              : const Color(0xFF00D4FF),
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),

              SizedBox(height: isMobile ? 12 : 14),

              /// PROGRESS DISPLAY - Different for PRO vs Non-PRO
              if (!isPro)
                /// Non-PRO: Single progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isExceeded
                          ? Colors.redAccent
                          : isNearLimit
                          ? Colors.orange
                          : const Color(0xFF00D4FF),
                    ),
                  ),
                )
              else
                /// PRO: Phased Nano & Mini model usage
                Builder(
                  builder: (context) {
                    final nanoUsed = userModel.aiNanoUsedToday;
                    final miniUsed = userModel.aiMiniUsedToday;
                    const miniCap =
                        20; // Phase 1: 20 mini/day (premium model first)
                    const nanoCap =
                        80; // Phase 2: 80 nano/day (after mini exhausted)

                    return Column(
                      children: [
                        /// MINI MODEL USAGE (Phase 1 — shown first)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'home.model_mini_premium'.tr(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: isMobile ? 11 : 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: AutoSizeText(
                                '$miniUsed / $miniCap',
                                style: TextStyle(
                                  color: miniUsed >= miniCap
                                      ? Colors.orange
                                      : Colors.amberAccent,
                                  fontSize: isMobile ? 10 : 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (miniUsed / miniCap).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: Colors.white.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              miniUsed >= miniCap
                                  ? Colors.red.shade400
                                  : Colors.amberAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        /// NANO MODEL USAGE (Phase 2 — shown second)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'home.model_nano'.tr(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: isMobile ? 11 : 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: AutoSizeText(
                                '$nanoUsed / $nanoCap',
                                style: TextStyle(
                                  color: nanoUsed >= nanoCap
                                      ? Colors.orange
                                      : Colors.purpleAccent,
                                  fontSize: isMobile ? 10 : 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (nanoUsed / nanoCap).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: Colors.white.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              nanoUsed >= nanoCap
                                  ? Colors.red.shade400
                                  : Colors.purpleAccent,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Ad Rewards Tracker (all non-PRO users) ──────────────────────────────
  Widget _buildAdRewardsCard(UserModel user, bool isMobile) {
    final int adsWatched = user.rewardedAdsWatchedToday;
    final int maxAds = user.maxRewardedAdsPerDay ?? 0;
    final int adReward = user.aiPerRewardedAd ?? 0;
    final int tokensEarned = adsWatched * adReward;
    final int maxTokens = maxAds * adReward;
    final bool allWatched = maxAds > 0 && adsWatched >= maxAds;
    final int displayMax = maxAds.clamp(1, 8); // max 8 slot indicators

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0D7377).withOpacity(0.85),
            const Color(0xFF14A085).withOpacity(0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14A085).withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF14A085)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.stars_rounded,
                  color: Colors.white,
                  size: isMobile ? 18 : 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoSizeText(
                      'profile.todays_ad_rewards'.tr(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      minFontSize: 11,
                      overflow: TextOverflow.visible,
                    ),
                    AutoSizeText(
                      allWatched
                          ? 'profile.max_earned_today'.tr()
                          : 'profile.tokens_earned_today'.tr(
                              namedArgs: {
                                'earned': '$tokensEarned',
                                'max': '$maxTokens',
                              },
                            ),
                      style: TextStyle(
                        color: allWatched ? Colors.greenAccent : Colors.white60,
                        fontSize: isMobile ? 11 : 12,
                      ),
                      maxLines: 1,
                      minFontSize: 9,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Visual ad slot indicators
          if (maxAds > 0)
            Row(
              children: List.generate(displayMax, (i) {
                final watched = i < adsWatched;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: watched
                          ? const LinearGradient(
                              colors: [Color(0xFF00D4FF), Color(0xFF14A085)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: watched ? null : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: watched
                            ? const Color(0xFF00D4FF).withOpacity(0.6)
                            : Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: Icon(
                      watched
                          ? Icons.play_arrow_rounded
                          : Icons.play_arrow_outlined,
                      color: watched ? Colors.white : Colors.white24,
                      size: 18,
                    ),
                  ),
                );
              }),
            ),

          const SizedBox(height: 10),

          // Footer stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, color: Colors.amber, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: AutoSizeText(
                        'profile.gen_per_ad'.tr(
                          namedArgs: {'count': '$adReward'},
                        ),
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: isMobile ? 11 : 12,
                        ),
                        maxLines: 2,
                        minFontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AutoSizeText(
                  allWatched
                      ? 'profile.max_earned_today'.tr()
                      : 'profile.ads_left'.tr(
                          namedArgs: {'count': '${maxAds - adsWatched}'},
                        ),
                  style: TextStyle(
                    color: allWatched ? Colors.greenAccent : Colors.white54,
                    fontSize: isMobile ? 11 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  minFontSize: 9,
                  overflow: TextOverflow.visible,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── How to Earn More (tier2 / tier3 non-PRO) ─────────────────────────────
  Widget _buildHowToEarnCard(UserModel user, bool isMobile) {
    final int adReward = user.aiPerRewardedAd ?? 0;
    final int maxAds = user.maxRewardedAdsPerDay ?? 0;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6C1FFF).withOpacity(0.22),
            const Color(0xFF9B59B6).withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.purple.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9B59B6), Color(0xFF6C1FFF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: isMobile ? 18 : 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoSizeText(
                      'profile.how_to_earn_title'.tr(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    AutoSizeText(
                      'profile.how_to_earn_sub'.tr(),
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: isMobile ? 11 : 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.withOpacity(0.4)),
                ),
                child: AutoSizeText(
                  user.regionTier.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.purpleAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Steps
          _buildEarnStep(
            Icons.play_circle_filled_rounded,
            '1',
            'profile.earn_step1'.tr(),
            Colors.cyan,
            isMobile,
          ),
          const SizedBox(height: 10),
          _buildEarnStep(
            Icons.bolt_rounded,
            '2',
            'profile.earn_step2'.tr(namedArgs: {'count': '$adReward'}),
            Colors.amber,
            isMobile,
          ),
          const SizedBox(height: 10),
          _buildEarnStep(
            Icons.refresh_rounded,
            '3',
            'profile.earn_step3'.tr(namedArgs: {'max': '$maxAds'}),
            Colors.purpleAccent,
            isMobile,
          ),

          const SizedBox(height: 14),

          // Reward summary pill
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.stars_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: AutoSizeText(
                    'profile.daily_potential'.tr(
                      namedArgs: {
                        'total': '${adReward * maxAds}',
                        'max': '$maxAds',
                      },
                    ),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarnStep(
    IconData icon,
    String step,
    String text,
    Color color,
    bool isMobile,
  ) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Center(child: Icon(icon, color: color, size: 15)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AutoSizeText(
            text,
            style: TextStyle(
              color: Colors.white70,
              fontSize: isMobile ? 12 : 13,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AutoSizeText(
              step,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumUpgradeCard(bool isMobile) {
    final proFeatures = [
      {
        'icon': Icons.all_inclusive_rounded,
        'text': 'profile.feature_unlimited'.tr(),
      },
      {'icon': Icons.bolt_rounded, 'text': 'profile.feature_priority'.tr()},
      {
        'icon': Icons.auto_awesome_rounded,
        'text': 'profile.feature_templates'.tr(),
      },
      {'icon': Icons.block_rounded, 'text': 'profile.feature_no_ads'.tr()},
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withOpacity(0.18),
            const Color(0xFFFFED4B).withOpacity(0.12),
            const Color(0xFFFAD94D).withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row with icon and title
          Row(
            children: [
              // Premium icon with glow
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFFD700),
                      Color(0xFFFFED4B),
                      Color(0xFFFAD94D),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: isMobile ? 22 : 26,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoSizeText(
                      'profile.upgrade_pro_title'.tr(),
                      style: TextStyle(
                        fontSize: isMobile ? 17 : 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 2,
                      minFontSize: isMobile ? 15 : 17,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                    const SizedBox(height: 2),
                    AutoSizeText(
                      'profile.unlock_potential'.tr(),
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        color: const Color(0xFFFFED4B).withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      minFontSize: isMobile ? 9 : 10,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: isMobile ? 16 : 20),

          // Feature points grid - 2 columns x 2 rows
          Row(
            children: [
              _buildFeatureItem(proFeatures[0], isMobile),
              const SizedBox(width: 8),
              _buildFeatureItem(proFeatures[1], isMobile),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildFeatureItem(proFeatures[2], isMobile),
              const SizedBox(width: 8),
              _buildFeatureItem(proFeatures[3], isMobile),
            ],
          ),

          SizedBox(height: isMobile ? 16 : 20),

          // Upgrade button
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/paywall');
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFFD700),
                    Color(0xFFFFED4B),
                    Color(0xFFFAD94D),
                  ],
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.rocket_launch_rounded,
                    size: isMobile ? 18 : 20,
                    color: const Color(0xFF1A1A2E),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: AutoSizeText(
                      'profile.upgrade_button'.tr(),
                      style: TextStyle(
                        color: const Color(0xFF1A1A2E),
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(Map<String, dynamic> feature, bool isMobile) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 12,
          vertical: isMobile ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(
              feature['icon'] as IconData,
              size: isMobile ? 14 : 16,
              color: const Color(0xFFFFED4B),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AutoSizeText(
                feature['text'] as String,
                style: TextStyle(
                  fontSize: isMobile ? 10 : 11,
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProWelcomeCard(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFED4B).withOpacity(0.10),
            const Color(0xFFFAD94D).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFED4B).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFED4B), Color(0xFFFAD94D)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF1A1A2E),
              size: 20,
            ),
          ),
          SizedBox(width: isMobile ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AutoSizeText(
                      'profile.plan_pro'.tr(),
                      style: TextStyle(
                        color: const Color(0xFFFFED4B),
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      minFontSize: 9,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFED4B).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: AutoSizeText(
                        'profile.status_active'.tr(),
                        style: TextStyle(
                          color: const Color(0xFFFFED4B),
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        minFontSize: 7,
                        overflow: TextOverflow.visible,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                AutoSizeText(
                  'profile.pro_welcome_message'.tr(),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: isMobile ? 12 : 13,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  minFontSize: isMobile ? 10 : 11,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E).withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.15),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AutoSizeText(
                  'profile.delete_account_title'.tr(),
                  maxLines: 2,
                  minFontSize: 12,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  'profile.delete_account_message'.tr(),
                  maxLines: 4,
                  minFontSize: 11,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.15),
                              ),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                          child: AutoSizeText(
                            'general.cancel'.tr(),
                            maxLines: 1,
                            minFontSize: 11,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade500,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            await _deleteAccount();
                          },
                          child: AutoSizeText(
                            'profile.delete_account_confirm'.tr(),
                            maxLines: 1,
                            minFontSize: 10,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    if (!mounted) return;

    // 🎯 CHECK TOKEN FRESHNESS FIRST before showing delete progress dialog
    debugPrint('🔍 Checking if token is stale before deletion...');

    try {
      final staleIndicator = await StaleDataDetector()
          .checkAuthTokenFreshness();

      if (staleIndicator.isStale) {
        debugPrint('🔴 Token is STALE - showing re-login dialog');
        if (!mounted) return;
        // Token is stale - show re-login dialog immediately
        await _showReauthenticationDialog(context);
        return; // Exit without showing delete progress
      }

      debugPrint('🟢 Token is FRESH - proceeding with deletion');
    } catch (e) {
      debugPrint('❌ Error checking token freshness: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AutoSizeText('errors.action_failed'.tr()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Token is fresh - show premium delete account dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1A2E).withOpacity(0.95),
                  const Color(0xFF16213E).withOpacity(0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimal progress indicator
                SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF00D4FF),
                        ),
                        backgroundColor: const Color(
                          0xFF00D4FF,
                        ).withOpacity(0.1),
                      ),
                      const Icon(
                        Icons.lock_rounded,
                        color: Color(0xFF00D4FF),
                        size: 28,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // Main title
                AutoSizeText(
                  'profile.delete_progress_title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                // Subtitle
                AutoSizeText(
                  'profile.delete_progress_subtitle'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade400,
                    height: 1.5,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                // Minimal step indicator - just dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMinimalStepDot(0),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(
                        width: 20,
                        height: 1,
                        color: const Color(0xFF00D4FF).withOpacity(0.3),
                      ),
                    ),
                    _buildMinimalStepDot(1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(
                        width: 20,
                        height: 1,
                        color: const Color(0xFF00D4FF).withOpacity(0.3),
                      ),
                    ),
                    _buildMinimalStepDot(2),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    bool deletionSucceeded = false;

    try {
      // ⏱️  Add timeout to prevent infinite loading if deletion hangs
      // Token freshness already verified before showing progress dialog
      await AuthRepository(UserService()).deleteAccount().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('profile.delete_timeout'.tr()),
      );
      deletionSucceeded = true;
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '❌ Firebase exception during deletion: ${e.code} - ${e.message}',
      );
      if (!mounted) return;

      // Show error dialog
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1A2E),
                  const Color(0xFF16213E).withOpacity(0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AutoSizeText(
                    'errors.action_failed'.tr(),
                    maxLines: 2,
                    minFontSize: 12,
                    overflow: TextOverflow.visible,
                    softWrap: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AutoSizeText(
                    'errors.something_went_wrong_try_again'.tr(),
                    maxLines: 4,
                    minFontSize: 11,
                    overflow: TextOverflow.visible,
                    softWrap: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade500,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: AutoSizeText(
                        'general.ok'.tr(),
                        maxLines: 1,
                        minFontSize: 10,
                        overflow: TextOverflow.visible,
                        softWrap: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } on TimeoutException catch (e) {
      debugPrint('⏱️  Account deletion timeout: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AutoSizeText('profile.delete_took_too_long'.tr()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('❌ Account deletion error: $e');
      if (!mounted) return;

      // Show error dialog instead of snackbar
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1A2E),
                  const Color(0xFF16213E).withOpacity(0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AutoSizeText(
                    'errors.action_failed'.tr(),
                    maxLines: 2,
                    minFontSize: 12,
                    overflow: TextOverflow.visible,
                    softWrap: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AutoSizeText(
                    e.toString(),
                    maxLines: 4,
                    minFontSize: 11,
                    overflow: TextOverflow.visible,
                    softWrap: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade500,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: AutoSizeText(
                        'general.ok'.tr(),
                        maxLines: 1,
                        minFontSize: 10,
                        overflow: TextOverflow.visible,
                        softWrap: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        // Always close the progress dialog first
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }

        // Handle successful deletion
        if (deletionSucceeded && mounted) {
          // Clear SharedPreferences after successful deletion
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            debugPrint('✅ SharedPreferences cleared after deletion');
          } catch (e) {
            debugPrint('❌ Error clearing SharedPreferences: $e');
          }

          // Change locale
          await context.setLocale(const Locale('en'));

          // Navigate immediately with no delay to prevent blank screen
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          }
        }
        // On error, stay on profile screen (error dialog already shown)
      }
    }
  }

  /// Show re-authentication dialog and handle re-auth flow
  Future<void> _showReauthenticationDialog(BuildContext context) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E).withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00D4FF).withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withOpacity(0.15),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AutoSizeText(
                  'profile.session_expired_title'.tr(),
                  maxLines: 2,
                  minFontSize: 12,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  'profile.session_expired_message'.tr(),
                  maxLines: 4,
                  minFontSize: 11,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.15),
                              ),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                          child: AutoSizeText(
                            'general.cancel'.tr(),
                            maxLines: 1,
                            minFontSize: 11,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D4FF),
                            foregroundColor: const Color(0xFF1A1A2E),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(dialogContext);

                            // Show logout progress
                            if (!mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                child: Center(
                                  child: SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: const AlwaysStoppedAnimation(
                                        Color(0xFF00D4FF),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );

                            try {
                              // 🔴 Token is stale - logout user for security
                              debugPrint(
                                '🔴 Token stale - logging out user...',
                              );
                              await AuthRepository(UserService()).logout();

                              if (!mounted) return;
                              Navigator.pop(context); // Close progress dialog

                              // Navigate to login screen
                              if (mounted) {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/login',
                                  (_) => false,
                                );
                              }
                            } catch (e) {
                              debugPrint('❌ Logout error: $e');
                              if (mounted && Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                              if (!mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: AutoSizeText(
                                    'errors.action_failed'.tr(),
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: AutoSizeText(
                            'profile.sign_in_again'.tr(),
                            maxLines: 1,
                            minFontSize: 11,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build minimal step indicator dot
  Widget _buildMinimalStepDot(int stepIndex) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF00D4FF), const Color(0xFF00FF88)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withOpacity(0.3),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
