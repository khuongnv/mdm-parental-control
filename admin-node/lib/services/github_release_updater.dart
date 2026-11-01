import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class GitHubReleaseInfo {
  final String tagName;
  final String title;
  final String apkDownloadUrl;
  final String releaseNotes;
  final String publishedAt;
  final int assetSize;

  GitHubReleaseInfo({
    required this.tagName,
    required this.title,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.assetSize,
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

  /// Lấy phiên bản app hiện tại từ hệ thống
  Future<String> getCurrentAppVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getAppVersion');
      return version ?? '1.1.0';
    } catch (_) {
      return '1.1.0';
    }
  }

  /// Lấy đường dẫn thư mục bộ nhớ tạm của app
  Future<String> getAppCacheDirectory() async {
    try {
      final dir = await _channel.invokeMethod<String>('getCacheDirectory');
      return dir ?? '/data/data/vn.hanoi.khuongnv.vfam.admin/cache';
    } catch (_) {
      return '/data/data/vn.hanoi.khuongnv.vfam.admin/cache';
    }
  }

  /// Kiểm tra bản cập nhật mới nhất từ GitHub Releases
  Future<GitHubReleaseInfo?> checkForUpdate(String currentVersion) async {
    final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'VFam-Admin-Updater',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tagName = data['tag_name'] as String;
        final name = (data['name'] as String?) ?? tagName;
        final body = (data['body'] as String?) ?? 'Bản cập nhật tối ưu hóa hiệu năng và vá lỗi.';
        final publishedAt = (data['published_at'] as String?) ?? '';

        final assets = (data['assets'] as List<dynamic>?) ?? [];
        String? downloadUrl;
        int assetSize = 0;

        for (final asset in assets) {
          final assetName = (asset['name'] as String).toLowerCase();
          if (assetName.contains('admin') || assetName.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String;
            assetSize = (asset['size'] as int?) ?? 0;
            break;
          }
        }

        // So sánh tag_name với phiên bản hiện tại
        final cleanTag = tagName.replaceAll('v', '').trim();
        final cleanCurrent = currentVersion.replaceAll('v', '').trim();

        if (downloadUrl != null && cleanTag != cleanCurrent) {
          return GitHubReleaseInfo(
            tagName: tagName,
            title: name,
            apkDownloadUrl: downloadUrl,
            releaseNotes: body,
            publishedAt: publishedAt,
            assetSize: assetSize,
          );
        }
      }
    } catch (_) {
      // Ignored
    }
    return null;
  }

  /// Tải file APK từ GitHub kèm theo callback theo dõi tiến trình (0.0 - 1.0)
  Future<File> downloadApk(
    String downloadUrl, {
    required Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(downloadUrl));
    request.headers['User-Agent'] = 'VFam-Admin-Updater';

    final response = await client.send(request);
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

  /// Gọi Intent mở trình cài đặt APK của Android
  Future<bool> installApk(File apkFile) async {
    try {
      final success = await _channel.invokeMethod<bool>('installApk', {
        'filePath': apkFile.absolute.path,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Lỗi khởi động cài đặt ứng dụng');
    }
  }
}
