// SPDX-License-Identifier: MIT

/// Keeps recovery storage stable when the product's visible name changes.
///
/// On Windows, path_provider 2.3.0 builds the application support directory
/// from CompanyName/ProductName. Runner.rc deliberately retains CompanyName
/// (com.example), while ProductName is now Color. Reuse the previous product
/// directory under that same company instead of moving or copying its files.
/// macOS uses the retained bundle identifier; Linux retains its application ID.
String recoveryDirectoryPath(
  String applicationSupportPath, {
  required bool windows,
}) {
  if (!windows) return '$applicationSupportPath/recovery';

  // Parse Windows paths explicitly so drive letters, UNC shares, spaces and
  // non-ASCII names also resolve correctly when tested on another platform.
  return Uri.directory(
    applicationSupportPath,
    windows: true,
  ).resolve('../edupaint_flutter_study/recovery').toFilePath(windows: true);
}

/// The private album of saved drawings: a folder beside the recovery one,
/// in the same place on every system for the same reasons.
String galleryDirectoryPath(
  String applicationSupportPath, {
  required bool windows,
}) {
  if (!windows) return '$applicationSupportPath/gallery';
  return Uri.directory(
    applicationSupportPath,
    windows: true,
  ).resolve('../edupaint_flutter_study/gallery').toFilePath(windows: true);
}

/// The file of the options, beside the two folders above for the same
/// reasons: the adult's choices follow Color from one version to the next.
String optionsFilePath(String applicationSupportPath, {required bool windows}) {
  if (!windows) return '$applicationSupportPath/options.json';
  return Uri.directory(
    applicationSupportPath,
    windows: true,
  ).resolve('../edupaint_flutter_study/options.json').toFilePath(windows: true);
}

/// Whether [path] names something placed directly in [folder]: the same
/// folder once both are written as absolute paths without a final separator.
/// Names are compared without regard to case where the system does not tell
/// « Gallery » from « gallery ». No file is read: a road through a link is
/// another name, and is not recognised.
bool isPlacedIn(
  String path,
  String folder, {
  required String separator,
  required bool caseSensitive,
}) {
  String tidy(String name) {
    var end = name.length;
    while (end > 1 && (name[end - 1] == '/' || name[end - 1] == separator)) {
      end--;
    }
    final tidied = name.substring(0, end);
    return caseSensitive ? tidied : tidied.toLowerCase();
  }

  final cut = path.lastIndexOf(separator);
  final other = separator == '/' ? cut : path.lastIndexOf('/');
  final last = cut > other ? cut : other;
  if (last < 0) return false;
  // Directly under the root, the folder is the root itself.
  return tidy(path.substring(0, last == 0 ? 1 : last)) == tidy(folder);
}
