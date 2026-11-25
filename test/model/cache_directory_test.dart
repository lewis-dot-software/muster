import 'package:grit/grit.dart';
import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/os.dart';
import 'package:test/test.dart';

/// The cache [variables] name on [os].
String? _cache(Map<String, String> variables, {Os os = .posix}) =>
    CacheDirectory.of((variables: variables, os: os))?.path;

void main() {
  test('MUSTER_CACHE is the cache where it is set', () {
    expect(
      _cache({
        'MUSTER_CACHE': '/c',
        'XDG_CACHE_HOME': '/x',
        'HOME': '/h',
        'LOCALAPPDATA': r'C:\l',
      }),
      '/c',
    );
  });

  test('XDG_CACHE_HOME holds the cache where MUSTER_CACHE is unset', () {
    expect(_cache({'XDG_CACHE_HOME': '/x', 'HOME': '/h'}), '/x/muster');
  });

  test('HOME holds the cache where neither is set', () {
    expect(_cache({'HOME': '/h'}), '/h/.cache/muster');
  });

  test('a relative XDG_CACHE_HOME is passed over for HOME', () {
    expect(_cache({'XDG_CACHE_HOME': 'x', 'HOME': '/h'}), '/h/.cache/muster');
  });

  test('a variable set empty counts as unset', () {
    expect(
      _cache({'MUSTER_CACHE': '', 'XDG_CACHE_HOME': '', 'HOME': '/h'}),
      '/h/.cache/muster',
    );
  });

  test('no cache where no variable it takes is set', () {
    expect(_cache({'LOCALAPPDATA': r'C:\l'}), isNull);
    expect(_cache({'HOME': ''}), isNull);
  });

  test('LOCALAPPDATA holds the cache on Windows, in its separators', () {
    expect(
      _cache({
        'LOCALAPPDATA': r'C:\Users\u\AppData\Local',
        'XDG_CACHE_HOME': '/x',
        'HOME': '/h',
      }, os: .windows),
      r'C:\Users\u\AppData\Local\muster',
    );
  });

  test('MUSTER_CACHE is the cache on Windows where it is set', () {
    expect(
      _cache({'MUSTER_CACHE': r'D:\c', 'LOCALAPPDATA': r'C:\l'}, os: .windows),
      r'D:\c',
    );
  });

  test('no cache on Windows where LOCALAPPDATA and MUSTER_CACHE are unset', () {
    expect(
      _cache({'HOME': '/h', 'XDG_CACHE_HOME': '/x'}, os: .windows),
      isNull,
    );
  });

  property(
    'STO-19: `MUSTER_CACHE` is the cache on either system, whatever else is '
    'set.',
    (Draw draw) {
      final String cache = draw(
        .string(alphabet: .of(r'aZ09/\ .:-_'), minLength: 1),
        label: 'cache',
      );
      final Map<String, String> others = {
        for (final String name in [
          'XDG_CACHE_HOME',
          'HOME',
          'LOCALAPPDATA',
          'PATH',
        ])
          if (draw(
                .element(<String?>[null, '', 'x', '/x', r'C:\x']),
                label: name,
              )
              case final String value)
            name: value,
      };
      final Os os = draw(.element(Os.values), label: 'os');
      expect(_cache({...others, 'MUSTER_CACHE': cache}, os: os), cache);
    },
  );
}
