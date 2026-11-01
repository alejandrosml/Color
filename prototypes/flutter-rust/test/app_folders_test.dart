// SPDX-License-Identifier: MIT
// P-01 of the retrospective of October 2026: the folders of Color without
// path_provider. On the iPhone, the iPad, the Mac and Android the program
// that carries Color names them; here, on Linux, the reader of the system
// does, as it did through path_provider. The trial of the devices checks
// that they are where path_provider put them.
import 'dart:io';

import 'package:edupaint_flutter_study/app_folders.dart';
import 'package:edupaint_flutter_study/device_self_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Folders extends PathProviderPlatform {
  _Folders(this.root, {this.missing = const {}});

  final String root;
  final Set<String> missing;

  String? _at(String name) => missing.contains(name) ? null : '$root/$name';

  @override
  Future<String?> getApplicationSupportPath() async => _at('support');

  @override
  Future<String?> getApplicationDocumentsPath() async => _at('documents');

  @override
  Future<String?> getTemporaryPath() async => _at('temporary');
}

void main() {
  late PathProviderPlatform before;
  late Directory scratch;

  setUp(() {
    before = PathProviderPlatform.instance;
    scratch = Directory.systemTemp.createTempSync('color-folders-');
  });

  tearDown(() {
    PathProviderPlatform.instance = before;
    scratch.deleteSync(recursive: true);
  });

  test('here the reader of the system names the three folders, and Color '
      'makes its own', () async {
    PathProviderPlatform.instance = _Folders(scratch.path);
    final support = await applicationSupportFolder();
    expect(support.path, '${scratch.path}/support');
    expect(support.existsSync(), isTrue);
    expect(
      (await applicationDocumentsFolder()).path,
      '${scratch.path}/documents',
    );
    expect((await temporaryFolder()).path, '${scratch.path}/temporary');
    // Asked again: the same folder, which is there already.
    expect((await applicationSupportFolder()).path, support.path);
  }, skip: !Platform.isLinux && !Platform.isWindows);

  test('a folder that the system does not give is said', () async {
    PathProviderPlatform.instance = _Folders(
      scratch.path,
      missing: {'documents'},
    );
    await expectLater(
      applicationDocumentsFolder(),
      throwsA(
        isA<MissingFolderException>().having(
          (error) => error.folder,
          'folder',
          'documents',
        ),
      ),
    );
    expect((await temporaryFolder()).path, '${scratch.path}/temporary');
  }, skip: !Platform.isLinux && !Platform.isWindows);

  group('the folders are where path_provider put them', () {
    test('on the iPhone and the iPad', () {
      const container = '/private/var/mobile/Containers/Data/Application/A1';
      expect(
        misplacedFolders(
          support: '$container/Library/Application Support',
          documents: '$container/Documents',
          temporary: '$container/Library/Caches',
          system: 'ios',
        ),
        isEmpty,
      );
      expect(
        misplacedFolders(
          support: '$container/Library/Application Support/fr.aisml.color',
          documents: '$container/Documents/Color',
          temporary: '$container/tmp',
          system: 'ios',
        ),
        ['support', 'documents', 'temporary'],
      );
    });

    test('on Android', () {
      const data = '/data/user/0/fr.aisml.color';
      expect(
        misplacedFolders(
          support: '$data/files',
          documents: '$data/app_flutter',
          temporary: '$data/cache',
          system: 'android',
        ),
        isEmpty,
      );
      expect(
        misplacedFolders(
          support: '$data/files',
          documents: '$data/files/documents',
          temporary: '$data/code_cache',
          system: 'android',
        ),
        ['documents', 'temporary'],
      );
    });

    test('on the Mac, with the identifier of Color after its own folder and '
        'the caches', () {
      const home = '/Users/enfant/Library/Containers/fr.aisml.color/Data';
      expect(
        misplacedFolders(
          support: '$home/Library/Application Support/fr.aisml.color',
          documents: '$home/Documents',
          temporary: '$home/Library/Caches/fr.aisml.color',
          system: 'macos',
        ),
        isEmpty,
      );
      expect(
        misplacedFolders(
          support: '$home/Library/Application Support',
          documents: '$home/Documents',
          temporary: '$home/Library/Caches',
          system: 'macos',
        ),
        ['support', 'temporary'],
      );
    });

    test('elsewhere nothing is checked', () {
      expect(
        misplacedFolders(
          support: '/x',
          documents: '/y',
          temporary: '/z',
          system: 'linux',
        ),
        isEmpty,
      );
    });
  });
}
