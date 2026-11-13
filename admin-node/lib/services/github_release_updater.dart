import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GitHubReleaseInfo {
  final String tagName;
  final String title;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;
  final int assetSize;
  final bool isIosOta;

  String get apkDownloadUrl => downloadUrl;

  GitHubReleaseInfo({
    required this.tagName,
    required this.title,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.assetSize,
    this.isIosOta = false,
  });
}

class ParentAppUpdater {
  static const MethodChannel _channel = MethodChannel('vn.hanoi.khuongnv.vfam.admin/updater');

  final String repoOwner;
  final String repoName;

  ParentAppUpdater({
    this.repoOwner = 'khuongnv',
    this.repoName = 'mdm-parental-control',
  });

  /// So sánh Semantic Versioning (SemVer)
  /// Chỉ trả về true nếu phiên bản remote lớn hơn phiên bản hiện tại
  static bool isNewerVersion(String remoteTag, String currentVersion) {
    final remoteNumbers = remoteTag
        .replaceAll(RegExp(r'[^\d.]'), '')
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final localNumbers = currentVersion
        .replaceAll(RegExp(r'[^\d.]'), '')
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();

    if (remoteNumbers.isEmpty || localNumbers.isEmpty) return false;

    final maxLen = remoteNumbers.length > localNumbers.length
        ? remoteNumbers.length
        : localNumbers.length;
    for (int i = 0; i < maxLen; i++) {
      final r = i < remoteNumbers.length ? remoteNumbers[i] : 0;
      final l = i < localNumbers.length ? localNumbers[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }

  /// Lấy phiên bản app hiện tại từ hệ thống
  Future<String> getCurrentAppVersion() async {
    try {
      if (Platform.isAndroid) {
        final version = await _channel.invokeMethod<String>('getAppVersion');
        return version ?? '1.2.0';
      }
      return '1.0.0';
    } catch (_) {
      return '1.0.0';
    }
  }

  /// Lấy đường dẫn thư mục bộ nhớ tạm của app
  Future<String> getAppCacheDirectory() async {
    try {
      if (Platform.isAndroid) {
        final dir = await _channel.invokeMethod<String>('getCacheDirectory');
        return dir ?? '/data/data/vn.hanoi.khuongnv.vfam.admin/cache';
      }
      return Directory.systemTemp.path;
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  /// Kiểm tra bản cập nhật mới nhất từ GitHub Releases phù hợp với nền tảng hiện tại
  Future<GitHubReleaseInfo?> checkForUpdate(String currentVersion) async {
    // Truy vấn danh sách release gần nhất để lọc theo đúng nền tảng (iOS vs Android)
    final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases?per_page=15');
    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'VFam-Admin-Updater',
        },
      );

      if (response.statusCode == 200) {
        final releases = jsonDecode(response.body) as List<dynamic>;
        
        final isIos = Platform.isIOS;
        final targetTagPrefix = isIos ? 'admin-ios-v' : 'admin-android-v';
        final fallbackTagPrefix = isIos ? 'admin-ios' : 'admin-v';

        for (final release in releases) {
          final data = release as Map<String, dynamic>;
          final tagName = (data['tag_name'] as String? ?? '').trim();
          
          // Chỉ chọn bản release dành riêng cho nền tảng hiện hành
          final isMatch = tagName.startsWith(targetTagPrefix) || (!isIos && tagName.startsWith(fallbackTagPrefix));
          if (!isMatch) continue;

          final name = (data['name'] as String?) ?? tagName;
          final body = (data['body'] as String?) ?? 'Bản cập nhật tối ưu hóa hiệu năng và vá lỗi.';
          final publishedAt = (data['published_at'] as String?) ?? '';
          final assets = (data['assets'] as List<dynamic>?) ?? [];

          String? downloadUrl;
          int assetSize = 0;

          if (isIos) {
            // Trên iOS: Tìm file manifest.plist để tạo link OTA itms-services
            String? manifestUrl;
            for (final asset in assets) {
              final assetName = (asset['name'] as String).toLowerCase();
              if (assetName == 'manifest.plist') {
                manifestUrl = asset['browser_download_url'] as String;
                break;
              }
            }
            // Fallback link manifest nếu chưa có trong assets
            manifestUrl ??= 'https://github.com/$repoOwner/$repoName/releases/download/$tagName/manifest.plist';
            downloadUrl = 'itms-services://?action=download-manifest&url=$manifestUrl';
          } else {
            // Trên Android: Tìm file APK
            for (final asset in assets) {
              final assetName = (asset['name'] as String).toLowerCase();
              if (assetName.contains('admin') && assetName.endsWith('.apk')) {
                downloadUrl = asset['browser_download_url'] as String;
                assetSize = (asset['size'] as int?) ?? 0;
                break;
              }
            }
          }

          final cleanTag = tagName.replaceAll(RegExp(r'^[a-zA-Z\-_]+'), '').replaceAll('v', '').trim();
          final cleanCurrent = currentVersion.replaceAll('v', '').trim();

          if (downloadUrl != null && isNewerVersion(cleanTag, cleanCurrent)) {
            return GitHubReleaseInfo(
              tagName: tagName,
              title: name,
              downloadUrl: downloadUrl,
              releaseNotes: body,
              publishedAt: publishedAt,
              assetSize: assetSize,
              isIosOta: isIos,
            );
          }
        }
      }
    } catch (_) {
      // Ignored
    }
    return null;
  }

  /// Tải file APK từ GitHub (dành riêng cho Android)
  Future<File> downloadApk(
    String downloadUrl, {
    required Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(downloadUrl));
    request.headers['User-Agent'] = 'VFam-Admin-Updater';
    request.followRedirects = true;
    request.maxRedirects = 5;

    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw Exception('Lỗi máy chủ tải file: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;

    final cacheDir = await getAppCacheDirectory();
    final filePath = '$cacheDir/vfam-admin-update.apk';
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      receivedBytes += chunk.length;
      sink.add(chunk);
      if (totalBytes > 0) {
        final progress = receivedBytes / totalBytes;
        onProgress(progress.clamp(0.0, 1.0), receivedBytes, totalBytes);
      }
    }

    await sink.flush();
    await sink.close();
    client.close();

    return file;
  }

  /// Thực thi cài đặt bản cập nhật:
  /// - Trên iOS: Mở link OTA itms-services để Apple OS tự động hiện popup cài đặt trực tiếp
  /// - Trên Android: Gọi PackageInstaller mở file APK
  Future<bool> executeUpdate(GitHubReleaseInfo release, {File? apkFile}) async {
    if (release.isIosOta) {
      final uri = Uri.parse(release.downloadUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } else {
      if (apkFile == null) return false;
      try {
        final success = await _channel.invokeMethod<bool>('installApk', {
          'filePath': apkFile.absolute.path,
        });
        return success ?? false;
      } catch (e) {
        rethrow;
      }
    }
  }

  /// Tương thích ngược: Gọi Intent mở trình cài đặt APK của Android
  Future<bool> installApk(File apkFile) async {
    try {
      final success = await _channel.invokeMethod<bool>('installApk', {
        'filePath': apkFile.absolute.path,
      });
      return success ?? false;
    } catch (e) {
      rethrow;
    }
  }
}
