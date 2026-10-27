#!/usr/bin/env python3
"""Build Color from canonical sources using a separate macOS staging directory.

Sources, reports and the pub cache may live on ExFAT. Keep the SDK, staging and
.app output on a macOS filesystem; deliver the resulting app externally as ZIP.
This script never changes SDK files or creates/moves SDK cache links itself.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_SOURCE = ROOT / 'prototypes/flutter-rust'
CORE_SOURCE = ROOT / 'prototypes/native-swift-rust/core/src/lib.rs'
# The folder cargo builds: Cargo.toml, Cargo.lock, .cargo/config.toml and the
# sources of the dependencies in vendor/. Nothing is downloaded.
CORE_FOLDER = CORE_SOURCE.parent.parent
RUST_TARGET = 'aarch64-apple-darwin'
PINNED_FLUTTER_COMMIT = '9584c6713b324636289d067944a46fd6b49df14b'
STAGING_MARKER = '.color-flutter-staging.json'
PUB_CACHE_MARKER = '.color-pub-cache-staging.json'
PUB_CACHE_MAX_BYTES = 165 * 1024 * 1024
EXCLUDED_DIRECTORIES = frozenset({'build', '.dart_tool', 'ephemeral', '.git'})
EXCLUDED_FILES = frozenset({'.flutter-plugins', '.flutter-plugins-dependencies', '.DS_Store'})


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true', help='Build Rust dylib only')
    parser.add_argument('--offline', action='store_true',
                        help='Resolve Flutter dependencies only from the existing pub cache')
    parser.add_argument('--test-concurrency', type=int,
                        help='Positive maximum number of concurrent Flutter test suites')
    parser.add_argument('--diagnostics', action='store_true',
                        help='Enable passive diagnostics in this bundle; no separate instance')
    parser.add_argument('--sdk-dir', type=Path, default=ROOT / 'build/flutter-toolchain/flutter',
                        help='Existing pinned Flutter SDK on a macOS filesystem (not copied or repaired)')
    parser.add_argument('--work-dir', type=Path, default=ROOT / 'build/flutter-study-work',
                        help='Separate internal staging directory; must be empty or owned by this script')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'build/flutter-study',
                        help='Local .app output; ExFAT is refused (deliver a ZIP to an external disk)')
    parser.add_argument('--report-dir', type=Path, default=ROOT / 'reports/flutter',
                        help='Build manifest and logs; may be on the external source disk')
    parser.add_argument('--pub-cache', type=Path, default=ROOT / 'build/flutter-toolchain/pub-cache',
                        help='Pub cache; defaults to the canonical source disk and may be on ExFAT')
    parser.add_argument('--cargo-target-dir', type=Path,
                        help='Where cargo compiles the Rust core, on a macOS filesystem; defaults to '
                             'macos-color-cargo-target beside --work-dir, which later builds reuse')
    parser.add_argument('--pub-cache-work-dir', type=Path,
                        help='Optional internal working copy of --pub-cache, excluding AppleDouble/Finder metadata; '
                             'must be empty or owned by this script (copy limited to 165 MiB)')
    args = parser.parse_args(argv)
    if args.test_concurrency is not None and args.test_concurrency < 1:
        parser.error('--test-concurrency must be a positive integer')
    return args


def paths_overlap(first, second):
    first, second = first.resolve(), second.resolve()
    return first == second or first in second.parents or second in first.parents


def validate_layout(source, core, sdk, work, output, report, pub_cache):
    """Reject staging/output layouts that could overwrite canonical inputs."""
    if work.is_symlink():
        raise ValueError('The staging directory itself must not be a symbolic link.')
    for name, path in [('canonical Flutter source', source), ('canonical Rust source', core.parent.parent),
                       ('SDK', sdk), ('output', output), ('reports', report), ('pub cache', pub_cache)]:
        if paths_overlap(work, path):
            raise ValueError(f'Staging must not overlap {name}: {path}')
    for name, path in [('canonical Flutter source', source), ('canonical Rust source', core.parent.parent),
                       ('SDK', sdk), ('pub cache', pub_cache)]:
        if paths_overlap(output, path):
            raise ValueError(f'Output must not overlap {name}: {path}')


def filesystem_from_mounts(mount_text, path):
    """Parse macOS mount output, choosing the longest containing mount point."""
    path = Path(path).resolve()
    best = None
    for line in mount_text.splitlines():
        match = re.match(r'^.+ on (.+) \(([^,()]+)(?:,|\))', line)
        if not match:
            continue
        mount_name = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m.group(1), 8)), match.group(1))
        mount = Path(mount_name)
        if path == mount or mount in path.parents:
            if best is None or len(mount.parts) > best[0]:
                best = (len(mount.parts), match.group(2).strip().lower())
    return best[1] if best else None


def detect_filesystem(path):
    """Read-only best effort; None means unknown, never a positive guarantee."""
    if sys.platform != 'darwin':
        return None
    probe = Path(path).resolve()
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    try:
        result = subprocess.run(['/usr/sbin/diskutil', 'info', '-plist', str(probe)],
                                capture_output=True, timeout=10, check=False)
        if result.returncode == 0:
            kind = plistlib.loads(result.stdout).get('FilesystemType')
            if isinstance(kind, str) and kind:
                return kind.lower()
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.TimeoutExpired):
        pass
    try:
        result = subprocess.run(['/sbin/mount'], capture_output=True, text=True,
                                timeout=10, check=False)
        if result.returncode == 0:
            return filesystem_from_mounts(result.stdout, probe)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def require_macos_filesystem(path, purpose, detector=detect_filesystem):
    kind = detector(path)
    if kind and ('exfat' in kind.lower() or kind.lower() in {'msdos', 'fat', 'fat32'}):
        raise ValueError(
            f'{purpose} cannot be on {kind}: {path}. Keep --sdk-dir, --work-dir, '
            '--output-dir and --cargo-target-dir on an internal macOS filesystem. Canonical sources, '
            '--pub-cache and --report-dir may stay on ExFAT. Deliver Color.app '
            'to the external disk as a ZIP preserving framework symbolic links; '
            'do not flatten the app bundle.')
    return kind


def _copy_directory_fd(source_fd, destination, relative=Path('.')):
    """Copy regular files via O_NOFOLLOW descriptors; never traverse a symlink."""
    files = total_bytes = 0
    with os.scandir(source_fd) as entries:
        for entry in entries:
            # These trees are generated; even a link bearing their name is omitted.
            if entry.name.startswith('._') or entry.name in EXCLUDED_DIRECTORIES or entry.name in EXCLUDED_FILES:
                continue
            if entry.name == STAGING_MARKER:
                raise ValueError(f'Reserved staging marker found in canonical sources: {relative / entry.name}')
            item_stat = entry.stat(follow_symlinks=False)
            item = relative / entry.name
            target = destination / entry.name
            if stat.S_ISLNK(item_stat.st_mode):
                raise ValueError(f'Source symbolic links are not followed or copied: {item}')
            if stat.S_ISDIR(item_stat.st_mode):
                child_fd = os.open(entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                   dir_fd=source_fd)
                try:
                    target.mkdir()
                    count, size = _copy_directory_fd(child_fd, target, item)
                    files += count
                    total_bytes += size
                finally:
                    os.close(child_fd)
            elif stat.S_ISREG(item_stat.st_mode):
                file_fd = os.open(entry.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=source_fd)
                with os.fdopen(file_fd, 'rb') as source_file:
                    actual = os.fstat(source_file.fileno())
                    if not stat.S_ISREG(actual.st_mode):
                        raise ValueError(f'Source is no longer a regular file: {item}')
                    with target.open('xb') as target_file:
                        shutil.copyfileobj(source_file, target_file, length=1024 * 1024)
                target.chmod(stat.S_IMODE(actual.st_mode) & 0o777)
                os.utime(target, ns=(actual.st_atime_ns, actual.st_mtime_ns))
                files += 1
                total_bytes += actual.st_size
            else:
                raise ValueError(f'Unsupported source file type: {item}')
    return files, total_bytes


def stage_flutter_sources(source, work):
    """Replace only an empty/owned staging tree, after a successful fresh copy.

    Call validate_layout first. A staging directory is exclusive to one build;
    concurrent builds must use different --work-dir and --output-dir values.
    """
    source, work = Path(source), Path(work)
    if source.is_symlink() or work.is_symlink():
        raise ValueError('Source and staging roots must not be symbolic links.')
    if paths_overlap(source, work):
        raise ValueError('Canonical sources and staging must be distinct, non-overlapping directories.')
    marker = {'schema': 1, 'tool': 'build-flutter-study.py', 'source': str(source.resolve())}
    if work.exists():
        if not work.is_dir():
            raise ValueError(f'Staging is not a directory: {work}')
        if any(work.iterdir()):
            marker_path = work / STAGING_MARKER
            try:
                fd = os.open(marker_path, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd, 'r') as marker_file:
                    observed = json.load(marker_file)
            except (OSError, ValueError) as error:
                raise ValueError(f'Refusing to replace unowned staging directory: {work}') from error
            if observed != marker:
                raise ValueError(f'Refusing to replace staging belonging to another source: {work}')
    work.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f'.{work.name}-staging-', dir=work.parent))
    backup = None
    try:
        source_fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            files, total_bytes = _copy_directory_fd(source_fd, temporary)
        finally:
            os.close(source_fd)
        (temporary / STAGING_MARKER).write_text(json.dumps(marker, indent=2) + '\n')
        if work.exists():
            backup = Path(tempfile.mkdtemp(prefix=f'.{work.name}-previous-', dir=work.parent))
            backup.rmdir()
            work.rename(backup)
        try:
            temporary.rename(work)
        except OSError:
            if backup is not None:
                backup.rename(work)
                backup = None
            raise
        return {'files': files, 'bytes': total_bytes,
                'excluded_directories': sorted(EXCLUDED_DIRECTORIES),
                'symlinks': 'rejected outside excluded generated directories'}
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
        if backup is not None and backup.exists():
            shutil.rmtree(backup)


def validate_pub_cache_work_layout(source, work, protected_paths=()):
    """Keep cache refreshes away from roots, sources and unrelated build paths."""
    source, work = Path(source).expanduser(), Path(work).expanduser()
    if source.is_symlink() or work.is_symlink():
        raise ValueError('Canonical and working pub-cache roots must not be symbolic links.')
    for path in (source, work):
        resolved = path.resolve()
        if resolved == Path(resolved.anchor):
            raise ValueError('A filesystem root cannot be used as a pub cache.')
    if paths_overlap(source, work):
        raise ValueError('Canonical and working pub caches must not overlap.')
    for name, path in protected_paths:
        if paths_overlap(work, Path(path).expanduser()):
            raise ValueError(f'Working pub cache must not overlap {name}: {path}')


def _copy_pub_cache_fd(source_fd, destination, manifest, state, max_bytes, relative=Path('.')):
    """Cache-specific copy: retain dependency build/target and useful dotfiles.

    AppleDouble and Finder metadata are omitted. Every other source must be a
    directory or regular file; links are rejected, never flattened or followed.
    Each written file is read back and SHA-256 checked before staging adoption.
    """
    with os.scandir(source_fd) as entries:
        for entry in entries:
            if entry.name.startswith('._') or entry.name == '.DS_Store':
                continue
            if entry.name == PUB_CACHE_MARKER:
                raise ValueError(f'Reserved cache marker in canonical pub cache: {relative / entry.name}')
            item = relative / entry.name
            target = destination / entry.name
            item_stat = entry.stat(follow_symlinks=False)
            if stat.S_ISLNK(item_stat.st_mode):
                raise ValueError(f'Pub-cache symbolic links are not followed or copied: {item}')
            if stat.S_ISDIR(item_stat.st_mode):
                child_fd = os.open(entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                   dir_fd=source_fd)
                try:
                    target.mkdir()
                    _copy_pub_cache_fd(child_fd, target, manifest, state, max_bytes, item)
                finally:
                    os.close(child_fd)
            elif stat.S_ISREG(item_stat.st_mode):
                file_fd = os.open(entry.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=source_fd)
                digest = hashlib.sha256()
                copied = 0
                with os.fdopen(file_fd, 'rb') as source_file:
                    before = os.fstat(source_file.fileno())
                    if not stat.S_ISREG(before.st_mode):
                        raise ValueError(f'Pub-cache source is no longer a regular file: {item}')
                    if state['bytes'] + before.st_size > max_bytes:
                        raise ValueError(f'Pub-cache copy exceeds {max_bytes} bytes; canonical cache is unchanged.')
                    with target.open('xb') as target_file:
                        while chunk := source_file.read(1024 * 1024):
                            if state['bytes'] + len(chunk) > max_bytes:
                                raise ValueError(f'Pub-cache copy exceeds {max_bytes} bytes; canonical cache is unchanged.')
                            target_file.write(chunk)
                            digest.update(chunk)
                            copied += len(chunk)
                            state['bytes'] += len(chunk)
                    after = os.fstat(source_file.fileno())
                    current = os.stat(entry.name, dir_fd=source_fd, follow_symlinks=False)
                    identity = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns)
                    if copied != before.st_size or identity(before) != identity(after) or identity(before) != identity(current):
                        raise ValueError(f'Canonical pub-cache file changed during copy: {item}')
                expected = digest.hexdigest()
                if target.stat().st_size != copied or sha256(target) != expected:
                    raise ValueError(f'Pub-cache copy verification failed: {item}')
                target.chmod(stat.S_IMODE(before.st_mode) & 0o777)
                os.utime(target, ns=(before.st_atime_ns, before.st_mtime_ns))
                manifest[str(item)] = {'bytes': copied, 'sha256': expected}
            else:
                raise ValueError(f'Unsupported pub-cache source type: {item}')


def stage_pub_cache(source, work, *, max_bytes=PUB_CACHE_MAX_BYTES):
    """Read-only canonical cache -> verified, privately owned working cache.

    The old working tree is replaced only after all files verify. Call the layout
    validator with build paths first; concurrent builds need separate caches.
    Refresh does not merge or write downloaded packages back to the canonical
    cache. At most max_bytes regular-file bytes are copied (165 MiB by default).
    """
    source, work = Path(source).expanduser(), Path(work).expanduser()
    validate_pub_cache_work_layout(source, work)
    if max_bytes < 0:
        raise ValueError('Pub-cache copy limit must be nonnegative.')
    marker = {'schema': 1, 'tool': 'build-flutter-study.py', 'kind': 'pub-cache',
              'source': str(source.resolve())}
    if work.exists():
        if not work.is_dir():
            raise ValueError(f'Working pub cache is not a directory: {work}')
        if any(work.iterdir()):
            try:
                fd = os.open(work / PUB_CACHE_MARKER, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                with os.fdopen(fd, 'r') as marker_file:
                    if not stat.S_ISREG(os.fstat(marker_file.fileno()).st_mode):
                        raise ValueError('Cache ownership marker is not a regular file.')
                    observed = json.load(marker_file)
            except (OSError, ValueError) as error:
                raise ValueError(f'Refusing to replace unowned working pub cache: {work}') from error
            if observed != marker:
                raise ValueError(f'Refusing to replace working pub cache belonging to another source: {work}')
    work.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f'.{work.name}-cache-', dir=work.parent))
    backup = None
    adopted = False
    try:
        manifest, state = {}, {'bytes': 0}
        source_fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            _copy_pub_cache_fd(source_fd, temporary, manifest, state, max_bytes)
        finally:
            os.close(source_fd)
        (temporary / PUB_CACHE_MARKER).write_text(json.dumps(marker, indent=2) + '\n')
        if work.exists():
            backup = Path(tempfile.mkdtemp(prefix=f'.{work.name}-previous-cache-', dir=work.parent))
            backup.rmdir()
            work.rename(backup)
        try:
            temporary.rename(work)
            adopted = True
        except OSError:
            if backup is not None:
                backup.rename(work)
                backup = None
            raise
        return {'files': len(manifest), 'bytes': state['bytes'], 'max_bytes': max_bytes,
                'manifest_sha256': hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest(),
                'verification': 'SHA-256 read-back for every regular file',
                'excluded_names': ['._*', '.DS_Store'], 'canonical_cache_modified': False,
                'symlinks': 'rejected outside excluded metadata'}
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
        if adopted and backup is not None and backup.exists():
            shutil.rmtree(backup)


def validate_cargo_target(target, protected_paths):
    """cargo writes its products there and nowhere near an input of the build."""
    if target.is_symlink():
        raise ValueError('The cargo target directory must not be a symbolic link.')
    for name, path in protected_paths:
        if paths_overlap(target, Path(path).expanduser()):
            raise ValueError(f'The cargo target directory must not overlap {name}: {path}')


def core_inputs(core_folder):
    """SHA-256 of what the core is built from, and one digest for vendor/."""
    def visible(path):
        # macOS leaves AppleDouble sidecars on ExFAT; they are not sources.
        return path.is_file() and not any(
            part.startswith('._') or part == '.DS_Store' for part in path.relative_to(core_folder).parts)
    files = {}
    for pattern in ('src/**/*.rs', 'include/*.h', 'art/**/*', 'sons/*', 'Cargo.toml', 'Cargo.lock',
                    '.cargo/config.toml', 'third-party-notices.txt'):
        for path in sorted(core_folder.glob(pattern)):
            if visible(path):
                files[path.relative_to(core_folder).as_posix()] = sha256(path)
    vendor = {path.relative_to(core_folder).as_posix(): sha256(path)
              for path in sorted((core_folder / 'vendor').rglob('*')) if visible(path)}
    crates = sum(1 for path in (core_folder / 'vendor').iterdir() if path.is_dir()) \
        if (core_folder / 'vendor').is_dir() else 0
    return files, {'crates': crates, 'files': len(vendor),
                   'sha256_of_the_list': hashlib.sha256(json.dumps(vendor, sort_keys=True).encode()).hexdigest()}


def install_library(source, target):
    """Put a compiled library at its place as a new file, never by rewriting
    the one that is there: macOS remembers the signature of a file it has
    loaded, and kills the program that loads other bytes under that memory."""
    source, target = Path(source), Path(target)
    temporary = target.with_name('.' + target.name + '.nouveau')
    shutil.copy2(source, temporary)
    os.replace(temporary, target)


def write_report(report_dir, **data):
    (report_dir / 'result.json').write_text(json.dumps(data, indent=2) + '\n')


def verify_sdk(sdk):
    commit = subprocess.check_output(['git', '-C', sdk, 'rev-parse', 'HEAD'], text=True).strip()
    if commit != PINNED_FLUTTER_COMMIT:
        raise ValueError('Review the documented accessibility regression before changing the pinned Flutter SDK '
                         f'(observed {commit}).')
    changes = subprocess.check_output(
        ['git', '-C', sdk, 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    if changes:
        raise ValueError('The pinned Flutter SDK contains tracked local changes. Review them before building.')
    return commit


def run(name, command, *, cwd, env, report_dir):
    print(name, flush=True)
    with (report_dir / (name + '.log')).open('w') as log:
        result = subprocess.run([str(a) for a in command], cwd=cwd, env=env,
                                stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        write_report(report_dir, status='failed', phase=name, exit_code=result.returncode,
                     updated_at_utc=datetime.now(timezone.utc).isoformat())
        raise SystemExit(f'{name} failed ({result.returncode}); see {report_dir / (name + ".log")}')


def sha256(path):
    with Path(path).open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def main(argv=None):
    args = parse_args(argv)
    # Check a lexical work-root link before resolving its parent path.
    validate_layout(APP_SOURCE, CORE_SOURCE, args.sdk_dir, args.work_dir,
                    args.output_dir, args.report_dir, args.pub_cache)
    if args.pub_cache_work_dir is not None:
        validate_pub_cache_work_layout(args.pub_cache, args.pub_cache_work_dir,
            [('canonical project', ROOT), ('SDK', args.sdk_dir), ('Flutter staging', args.work_dir),
             ('output', args.output_dir), ('reports', args.report_dir),
             ('Flutter configuration', args.work_dir.expanduser().parent / 'flutter-config')])
    cargo_target = args.cargo_target_dir or args.work_dir.expanduser().parent / 'macos-color-cargo-target'
    validate_cargo_target(cargo_target, [
        ('canonical Flutter source', APP_SOURCE), ('canonical Rust source', CORE_FOLDER),
        ('SDK', args.sdk_dir), ('Flutter staging', args.work_dir), ('output', args.output_dir),
        ('reports', args.report_dir), ('pub cache', args.pub_cache)])
    sdk, work, output, report_dir, pub_cache, cargo_target = [p.expanduser().resolve() for p in
        (args.sdk_dir, args.work_dir, args.output_dir, args.report_dir, args.pub_cache, cargo_target)]
    filesystems = {name: require_macos_filesystem(path, name) for name, path in
                   [('SDK', sdk), ('staging', work), ('macOS .app output', output),
                    ('cargo target', cargo_target)]}
    pub_cache_work = args.pub_cache_work_dir.expanduser().resolve() if args.pub_cache_work_dir else None
    effective_pub_cache = pub_cache_work or pub_cache
    cache_staging = None
    if pub_cache_work is not None:
        filesystems['working pub cache'] = require_macos_filesystem(pub_cache_work, 'working pub cache')
    if any(value is None for value in filesystems.values()):
        print('Filesystem type could not be detected for every local build path; '
              'ensure SDK, staging and .app output support macOS symbolic links.', file=sys.stderr)
    report_dir.mkdir(parents=True, exist_ok=True)
    write_report(report_dir, status='in_progress', started_at_utc=datetime.now(timezone.utc).isoformat())
    try:
        sdk_commit = verify_sdk(sdk)
    except (ValueError, subprocess.CalledProcessError) as error:
        write_report(report_dir, status='failed', phase='sdk_guard', reason=str(error))
        raise
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(FLUTTER_SUPPRESS_ANALYTICS='true', CI='true', PUB_CACHE=str(effective_pub_cache),
               XDG_CONFIG_HOME=str(work.parent / 'flutter-config'), MACOSX_DEPLOYMENT_TARGET='26.6')
    flutter, dart = sdk / 'bin/flutter', sdk / 'bin/dart'
    core = CORE_SOURCE  # Always canonical, including when ROOT is on ExFAT.
    dylib = output / 'libedupaint_core.dylib'
    env['EDUPAINT_CORE_LIBRARY'] = str(dylib)

    def command(name, arguments, cwd=APP_SOURCE):
        run(name, arguments, cwd=cwd, env=env, report_dir=report_dir)

    # cargo, from the folder of the core: its .cargo/config.toml names vendor/
    # as the only source of the dependencies. --frozen: the lock file as it
    # is, and no network. The last arguments go to the compiler of the core
    # itself, as when rustc built it alone.
    cargo = shutil.which('cargo')
    if cargo is None:
        write_report(report_dir, status='failed', phase='rust-dylib',
                     reason='cargo is not on the PATH; it comes with the Rust of Homebrew (brew install rust).')
        raise SystemExit('rust-dylib failed: cargo is not on the PATH.')
    env['CARGO_TARGET_DIR'] = str(cargo_target)
    # Said in plain words before cargo says it in its own: a copy of the
    # sources that lost files of vendor/ cannot be built.
    command('rust-vendored-sources', [sys.executable, ROOT / 'scripts/check-vendored-sources.py', CORE_FOLDER],
            cwd=CORE_FOLDER)
    command('rust-dylib', [cargo, 'rustc', '--release', '--lib', '--offline', '--frozen',
        '--target', RUST_TARGET, '--',
        '-C', 'link-arg=-Wl,-install_name,@rpath/libedupaint_core.dylib'], cwd=CORE_FOLDER)
    install_library(cargo_target / RUST_TARGET / 'release/libedupaint_core.dylib', dylib)
    if args.prepare_only:
        write_report(report_dir, status='prepared_only', core_source=str(core),
                     scope='Rust library built; Flutter application not staged, built or tested')
        return 0
    if pub_cache_work is not None:
        try:
            cache_staging = stage_pub_cache(pub_cache, pub_cache_work)
        except (OSError, ValueError) as error:
            write_report(report_dir, status='failed', phase='pub_cache_staging', reason=str(error))
            raise
    try:
        staging = stage_flutter_sources(APP_SOURCE, work)
    except (OSError, ValueError) as error:
        write_report(report_dir, status='failed', phase='source_staging', reason=str(error))
        raise
    command('pub-get', [flutter, 'pub', 'get', *(['--offline'] if args.offline else [])], cwd=work)
    command('analyze', [flutter, 'analyze', '--no-pub'], cwd=work)
    command('dart-rust-bridge', [dart, 'run', 'lib/rust_document.dart', '--self-test', dylib], cwd=work)
    test_options = ['--concurrency', str(args.test_concurrency)] if args.test_concurrency else []
    command('flutter-tests', [flutter, 'test', '--no-pub', *test_options], cwd=work)
    command('macos-release-build', [flutter, 'build', 'macos', '--release', '--no-pub'], cwd=work)
    built = work / 'build/macos/Build/Products/Release/Color.app'
    app = output / built.name
    if app.is_symlink():
        raise ValueError(f'Refusing to replace an app output symbolic link: {app}')
    if app.exists():
        shutil.rmtree(app)
    # Framework links must remain links; never flatten for ExFAT compatibility.
    shutil.copytree(built, app, symlinks=True)
    diagnostics_marker = app / 'Contents/Resources/edupaint-diagnostics.enabled'
    if args.diagnostics:
        diagnostics_marker.write_text('Passive visibility diagnostics explicitly enabled by build script.\n')
    else:
        diagnostics_marker.unlink(missing_ok=True)
    embedded = app / 'Contents/Frameworks/libedupaint_core.dylib'
    install_library(dylib, embedded)
    command('sign-rust-library', ['/usr/bin/codesign', '--force', '--sign', '-', embedded], cwd=work)
    command('sign-app', ['/usr/bin/codesign', '--force', '--sign', '-', '--entitlements',
                        work / 'macos/Runner/Release.entitlements', app], cwd=work)
    command('verify-signature', ['/usr/bin/codesign', '--verify', '--deep', '--strict', app], cwd=work)
    with (app / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    architecture = subprocess.check_output(['/usr/bin/file', binary], text=True).strip()
    verify_sdk(sdk)
    core_files, core_vendor = core_inputs(CORE_FOLDER)
    report = dict(status='passed', flutter_commit=sdk_commit,
        flutter_engine_revision=(sdk / 'bin/cache/engine.stamp').read_text().strip(),
        flutter_sdk_tracked_clean=True, sdk_directory=str(sdk), pub_cache=str(effective_pub_cache),
        canonical_pub_cache=str(pub_cache), pub_cache_work_directory=str(pub_cache_work) if pub_cache_work else None,
        pub_cache_staging=cache_staging,
        canonical_application_source=str(APP_SOURCE), build_application_source=str(work),
        canonical_core_source=str(core), detected_local_filesystems=filesystems, staging=staging,
        application_version=info.get('CFBundleShortVersionString'),
        application_build=info.get('CFBundleVersion'), application_name=info.get('CFBundleName'),
        bundle_identifier=info.get('CFBundleIdentifier'), diagnostics_enabled=args.diagnostics,
        app=str(app), architecture=architecture, minimum_macos=info.get('LSMinimumSystemVersion'),
        built_at_utc=datetime.now(timezone.utc).isoformat(), application_binary_sha256=sha256(binary),
        dart_aot_sha256=sha256(app / 'Contents/Frameworks/App.framework/App'),
        rust_dylib_sha256=sha256(embedded), core_source_sha256=sha256(core),
        core_source_files_sha256=core_files, core_vendored_sources=core_vendor,
        core_build='cargo rustc --release --lib --offline --frozen --target ' + RUST_TARGET
                   + ', dependencies from vendor/ only',
        cargo_target_directory=str(cargo_target),
        application_source_sha256={str(p.relative_to(work)): sha256(p)
            for p in sorted([*work.glob('lib/*.dart'), *work.glob('macos/Runner/*.swift'),
                *work.glob('macos/Runner/Configs/*.xcconfig'),
                *work.glob('macos/Runner.xcodeproj/xcshareddata/xcschemes/*.xcscheme'),
                work / 'macos/Runner/Info.plist', work / 'macos/Runner.xcodeproj/project.pbxproj',
                work / 'pubspec.yaml'])},
        dependency_resolution='offline cache only' if args.offline else 'normal pub resolution',
        flutter_test_concurrency=args.test_concurrency, build_script_sha256=sha256(__file__),
        pub_get='passed in fresh staging', dart_rust_bridge='passed',
        flutter_tests='passed; see flutter-tests.log', analyze='passed', build_mode='release',
        signing='ad hoc local only; no notarization',
        external_delivery='ZIP preserving bundle symbolic links; extract to a macOS filesystem',
        scope='macOS build plus unit/bridge tests; interactive and other-platform results recorded separately')
    write_report(report_dir, **report)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
