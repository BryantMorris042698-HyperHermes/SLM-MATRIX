import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub repository that publishes the APK as a Release asset.
/// Change these if you fork the project.
const String kUpdateOwner = 'bryantmorris042698-hyperhermes';
const String kUpdateRepo = 'slm-matrix';

/// Describes an available newer release found on GitHub.
class UpdateInfo {
  final String version; // normalized, e.g. "0.2.0"
  final String tagName; // raw tag, e.g. "v0.2.0"
  final String apkUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.releaseNotes,
  });
}

typedef ProgressCallback = void Function(double fraction);

/// Checks GitHub Releases for a newer APK and installs it. Android-only:
/// the install step launches the system package installer, which requires
/// the REQUEST_INSTALL_PACKAGES permission (declared in AndroidManifest).
class Updater {
  static Uri get _latestReleaseUri => Uri.parse(
        'https://api.github.com/repos/$kUpdateOwner/$kUpdateRepo/releases/latest',
      );

  /// Returns update info if a newer release with an APK asset exists, else null.
  Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final response = await http.get(
      _latestReleaseUri,
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      return null;
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final tagName = json['tag_name']?.toString() ?? '';
    final latest = _normalizeVersion(tagName);
    if (latest == null) {
      return null;
    }

    final assets = json['assets'];
    String? apkUrl;
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map &&
            asset['name'].toString().toLowerCase().endsWith('.apk')) {
          apkUrl = asset['browser_download_url']?.toString();
          break;
        }
      }
    }
    if (apkUrl == null) {
      return null;
    }

    final info = await PackageInfo.fromPlatform();
    final current = _normalizeVersion(info.version);
    if (current != null && !_isNewer(latest, current)) {
      return null;
    }

    return UpdateInfo(
      version: latest.join('.'),
      tagName: tagName,
      apkUrl: apkUrl,
      releaseNotes: json['body']?.toString() ?? '',
    );
  }

  /// Downloads the APK to the temp dir and launches the installer.
  Future<void> downloadAndInstall(
    UpdateInfo update, {
    ProgressCallback? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(update.apkUrl));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw HttpException('Download failed (${response.statusCode})');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/orca-mobile-${update.tagName}.apk');
    final sink = file.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress?.call(received / total);
      }
    }
    await sink.close();

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception('Could not open installer: ${result.message}');
    }
  }

  /// Parse "orca-v1.2.3" / "v1.2.3" / "1.2.3+4" → [1, 2, 3]; null if unparseable.
  /// Strips any leading non-digit prefix (e.g. the "orca-v" release-tag prefix).
  static List<int>? _normalizeVersion(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[^0-9]+'), '');
    final core = cleaned.split('+').first.split('-').first;
    final parts = core.split('.');
    if (parts.isEmpty) {
      return null;
    }
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) {
        return null;
      }
      nums.add(n);
    }
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums;
  }

  static bool _isNewer(List<int> candidate, List<int> current) {
    for (var i = 0; i < candidate.length && i < current.length; i++) {
      if (candidate[i] > current[i]) return true;
      if (candidate[i] < current[i]) return false;
    }
    return candidate.length > current.length;
  }
}
