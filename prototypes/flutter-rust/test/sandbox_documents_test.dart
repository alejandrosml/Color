// SPDX-License-Identifier: MIT
import 'package:edupaint_flutter_study/studio_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the panels open on the Documents of the person, not in the container', () {
    expect(
      userDocumentsOutsideSandbox(
        '/Users/alice/Library/Containers/fr.aisml.color/Data/Documents',
      ),
      '/Users/alice/Documents',
    );
    // Outside a container, on iOS, Android, Windows or Linux: unchanged.
    for (final path in [
      '/Users/alice/Documents',
      '/var/mobile/Containers/Data/Application/1234/Documents',
      '/data/user/0/fr.aisml.color/app_flutter',
      r'C:\Users\alice\Documents',
      '/home/alice/Documents',
    ]) {
      expect(userDocumentsOutsideSandbox(path), path, reason: path);
    }
  });
}
