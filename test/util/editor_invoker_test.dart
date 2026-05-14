import 'package:test/test.dart';

import 'package:taglibro_cli/src/util/editor_invoker.dart';

void main() {
  group('EditorInvoker.resolveEditorFrom', () {
    test('uses EDITOR when set', () {
      final picked = EditorInvoker.resolveEditorFrom(
        environment: const {'EDITOR': 'nvim'},
        isWindows: false,
        hasOnPath: (_) => fail('should not probe PATH when EDITOR is set'),
      );
      expect(picked, 'nvim');
    });

    test('uses VISUAL when EDITOR is empty', () {
      final picked = EditorInvoker.resolveEditorFrom(
        environment: const {'EDITOR': '', 'VISUAL': 'emacs -nw'},
        isWindows: false,
        hasOnPath: (_) => fail('should not probe PATH when VISUAL is set'),
      );
      expect(picked, 'emacs -nw');
    });

    test('POSIX fallback ladder: nano → vim → vi (first hit wins)', () {
      final picked = EditorInvoker.resolveEditorFrom(
        environment: const {},
        isWindows: false,
        hasOnPath: (bin) => bin == 'vim',
      );
      expect(picked, 'vim');
    });

    test('POSIX: returns null when nothing in the ladder is on PATH', () {
      final picked = EditorInvoker.resolveEditorFrom(
        environment: const {},
        isWindows: false,
        hasOnPath: (_) => false,
      );
      expect(picked, isNull);
    });

    test('Windows fallback: prefers notepad.exe on PATH', () {
      final probed = <String>[];
      final picked = EditorInvoker.resolveEditorFrom(
        environment: const {},
        isWindows: true,
        hasOnPath: (bin) {
          probed.add(bin);
          return bin == 'notepad.exe';
        },
      );
      expect(picked, 'notepad.exe');
      expect(probed.first, 'notepad.exe');
    });

    test(
        'Windows: falls back to bare "notepad.exe" even if PATH probe missed',
        () {
      // notepad.exe ships with Windows itself (System32). If for some
      // reason it isn't on PATH we still want to invoke it by name —
      // Process.start("notepad.exe") will hit it via the OS search.
      final picked = EditorInvoker.resolveEditorFrom(
        environment: const {},
        isWindows: true,
        hasOnPath: (_) => false,
      );
      expect(picked, 'notepad.exe');
    });

    test('Windows: honours user-set EDITOR over the ladder', () {
      final picked = EditorInvoker.resolveEditorFrom(
        environment: const {'EDITOR': 'code --wait'},
        isWindows: true,
        hasOnPath: (_) => fail('should not probe when EDITOR is set'),
      );
      expect(picked, 'code --wait');
    });
  });
}
