import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:taglibro_cli/src/util/config_store.dart';
import 'package:taglibro_cli/src/util/date_parser.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('taglibro-config-test-');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('loadDateFormat returns defaults when file is missing', () {
    final store = ConfigStore(
      overridePath: p.join(tmp.path, 'missing.json'),
    );
    expect(store.exists(), isFalse);
    final pref = store.loadDateFormat();
    expect(pref.order, DateOrder.ymd);
    expect(pref.separator, '-');
  });

  test('save → load round-trip preserves order + separator', () {
    final store = ConfigStore(
      overridePath: p.join(tmp.path, 'config.json'),
    );
    store.saveDateFormat(
      const DateFormatPref(order: DateOrder.dmy, separator: '.'),
    );
    expect(store.exists(), isTrue);
    final loaded = store.loadDateFormat();
    expect(loaded.order, DateOrder.dmy);
    expect(loaded.separator, '.');
  });

  test('save preserves unrelated top-level fields', () {
    final path = p.join(tmp.path, 'config.json');
    File(path).writeAsStringSync('''
{
  "schema_version": 1,
  "future_setting": {"hello": "world"}
}
''');
    final store = ConfigStore(overridePath: path);
    store.saveDateFormat(
      const DateFormatPref(order: DateOrder.mdy, separator: '_'),
    );
    final raw = File(path).readAsStringSync();
    expect(raw, contains('future_setting'));
    expect(raw, contains('hello'));
    // round-trip new field is also there
    expect(store.loadDateFormat().order, DateOrder.mdy);
  });

  test('compact separator survives the round-trip as ""', () {
    final store = ConfigStore(
      overridePath: p.join(tmp.path, 'config.json'),
    );
    store.saveDateFormat(
      const DateFormatPref(order: DateOrder.ymd, separator: ''),
    );
    final loaded = store.loadDateFormat();
    expect(loaded.separator, '');
  });

  test('colon separator round-trips intact', () {
    final store = ConfigStore(
      overridePath: p.join(tmp.path, 'config.json'),
    );
    store.saveDateFormat(
      const DateFormatPref(order: DateOrder.ymd, separator: ':'),
    );
    expect(store.loadDateFormat().separator, ':');
  });

  group('resolveDefaultPath', () {
    test('Linux/macOS: XDG_CONFIG_HOME wins when set', () {
      final path = ConfigStore.resolveDefaultPath(
        isWindows: false,
        environment: {
          'XDG_CONFIG_HOME': '/x/cfg',
          'HOME': '/home/u',
        },
      );
      // Compare via `p.join` so the expected value uses the host OS
      // separator — Windows CI joins with `\`, POSIX with `/`. This
      // mirrors `credentials_store_test.dart`.
      expect(path, p.join('/x/cfg', 'taglibro', 'config.json'));
    });

    test('Linux/macOS: falls back to \$HOME/.config when XDG unset', () {
      final path = ConfigStore.resolveDefaultPath(
        isWindows: false,
        environment: {'HOME': '/home/u'},
      );
      expect(path, p.join('/home/u', '.config', 'taglibro', 'config.json'));
    });

    test('Windows: uses %APPDATA%', () {
      final path = ConfigStore.resolveDefaultPath(
        isWindows: true,
        environment: {'APPDATA': r'C:\Users\Foo\AppData\Roaming'},
      );
      expect(
        path,
        contains('taglibro'),
      );
      expect(path, contains('config.json'));
    });

    test('Windows: throws when APPDATA is unset', () {
      expect(
        () => ConfigStore.resolveDefaultPath(
          isWindows: true,
          environment: const {},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Linux/macOS: throws when both XDG and HOME unset', () {
      expect(
        () => ConfigStore.resolveDefaultPath(
          isWindows: false,
          environment: const {},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
