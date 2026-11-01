import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubReleaseInfo {
  final String tagName;
  final String apkDownloadUrl;
  final String releaseNotes;
  final String publishedAt;

  GitHubReleaseInfo({
    required this.tagName,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });
}

class ParentAppUpdater {
  final String repoOwner;
  final String repoName;

  ParentAppUpdater({
    this.repoOwner = 'khuongnv',
    this.repoName = 'mdm-parental-control',
  });

  /// Kiểm tra bản cập nhật mới nhất từ GitHub Releases
  Future<GitHubReleaseInfo?> checkForUpdate(String currentVersion) async {
    final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'MDM-Parent-Admin-App',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tagName = data['tag_name'] as String;
        final body = (data['body'] as String?) ?? '';
        final publishedAt = (data['published_at'] as String?) ?? '';

        final assets = (data['assets'] as List<dynamic>?) ?? [];
        String? downloadUrl;
        for (final asset in assets) {
          final name = (asset['name'] as String).toLowerCase();
          if (name.contains('admin') || name.contains('parent') || name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String;
            break;
          }
        }

        if (downloadUrl != null && tagName != currentVersion) {
          return GitHubReleaseInfo(
            tagName: tagName,
            apkDownloadUrl: downloadUrl,
            releaseNotes: body,
            publishedAt: publishedAt,
          );
        }
      }
    } catch (_) {
      // Ignored
    }
    return null;
  }
}
