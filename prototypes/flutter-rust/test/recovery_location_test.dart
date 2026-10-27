// SPDX-License-Identifier: MIT
import 'package:edupaint_flutter_study/recovery_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows branding keeps the previous recovery location', () {
    const parent = r'C:\Users\Alice\AppData\Roaming\com.example';
    final before = recoveryDirectoryPath(
      '$parent\\edupaint_flutter_study',
      windows: true,
    );
    final after = recoveryDirectoryPath('$parent\\Color', windows: true);
    expect(after, before);
    expect(after, '$parent\\edupaint_flutter_study\\recovery');
  });

  test('Windows recovery respects UNC, Unicode and trailing separators', () {
    const cases = {
      'D:\\Profils\\Éloïse Martin\\com.example\\Color\\': 'D:\\Profils\\Éloïse Martin\\com.example\\edupaint_flutter_study\\recovery',
      r'\\server\Profiles\Alice\com.example\Color': r'\\server\Profiles\Alice\com.example\edupaint_flutter_study\recovery',
      'C:/Users/Alice/AppData/Roaming/com.example/Color/': r'C:\Users\Alice\AppData\Roaming\com.example\edupaint_flutter_study\recovery',
    };
    for (final entry in cases.entries) {
      expect(
        recoveryDirectoryPath(entry.key, windows: true),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('macOS and Linux retain their existing application support paths', () {
    const paths = [
      '/Users/Alice/Library/Application Support/org.edupaint.flutterstudy',
      '/home/alice/.local/share/com.example.edupaint_flutter_study',
    ];
    for (final path in paths) {
      expect(recoveryDirectoryPath(path, windows: false), '$path/recovery');
    }
  });

  test('the album lives beside the recovery folder, on every system', () {
    const windowsParent = r'C:\Users\Alice\AppData\Roaming\com.example';
    for (final product in ['Color', 'edupaint_flutter_study']) {
      expect(
        galleryDirectoryPath('$windowsParent\\$product', windows: true),
        '$windowsParent\\edupaint_flutter_study\\gallery',
      );
    }
    expect(
      galleryDirectoryPath(
        r'\\server\Profiles\Éloïse\com.example\Color',
        windows: true,
      ),
      r'\\server\Profiles\Éloïse\com.example\edupaint_flutter_study\gallery',
    );
    const paths = [
      '/Users/Alice/Library/Application Support/org.edupaint.flutterstudy',
      '/home/alice/.local/share/com.example.edupaint_flutter_study',
    ];
    for (final path in paths) {
      expect(galleryDirectoryPath(path, windows: false), '$path/gallery');
      // Two folders, never one inside the other, never the folder itself.
      expect(
        galleryDirectoryPath(path, windows: false),
        isNot(recoveryDirectoryPath(path, windows: false)),
      );
      expect(galleryDirectoryPath(path, windows: false), isNot(path));
    }
    expect(
      galleryDirectoryPath('$windowsParent\\Color', windows: true),
      isNot(recoveryDirectoryPath('$windowsParent\\Color', windows: true)),
    );
  });

  test('a path is placed in a folder when its own folder is that one', () {
    bool placed(String path, String folder, {bool caseSensitive = true}) =>
        isPlacedIn(path, folder, separator: '/', caseSensitive: caseSensitive);
    expect(placed('/a/b/gallery/Chat.edupaint', '/a/b/gallery'), isTrue);
    expect(placed('/a/b/gallery/Chat.edupaint', '/a/b/gallery/'), isTrue);
    expect(placed('/a/b/gallery/x/Chat.edupaint', '/a/b/gallery'), isFalse);
    expect(placed('/a/b/Chat.edupaint', '/a/b/gallery'), isFalse);
    expect(placed('/a/b/gallery-2/Chat.edupaint', '/a/b/gallery'), isFalse);
    expect(placed('/a/b/Gallery/Chat.edupaint', '/a/b/gallery'), isFalse);
    expect(
      placed(
        '/a/b/Gallery/Chat.edupaint',
        '/a/b/gallery',
        caseSensitive: false,
      ),
      isTrue,
    );
    expect(placed('Chat.edupaint', '/a/b/gallery'), isFalse);
    expect(placed('/Chat.edupaint', '/'), isTrue);
    expect(placed('/Chat.edupaint', '/a'), isFalse);
    // Windows: both separators are understood.
    bool onWindows(String path, String folder) =>
        isPlacedIn(path, folder, separator: r'\', caseSensitive: false);
    expect(
      onWindows(r'C:\Color\gallery\Chat.edupaint', r'C:\Color\gallery'),
      isTrue,
    );
    expect(
      onWindows(r'C:\Color\GALLERY\Chat.edupaint', r'c:\color\gallery\'),
      isTrue,
    );
    expect(
      onWindows('C:/Color/gallery/Chat.edupaint', 'C:/Color/gallery'),
      isTrue,
    );
    expect(onWindows(r'C:\Color\Chat.edupaint', r'C:\Color\gallery'), isFalse);
  });
}
