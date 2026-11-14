import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/read_status.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/worktree.dart';
import 'package:test/test.dart';

void main() {
  final String hash = 'a' * 40;

  test('a status with no entry past its headers is its head, unchanged', () {
    final Worktree? worktree = readStatus(
      '# branch.oid $hash\x00# branch.head (detached)\x00',
    );
    expect(worktree?.head, Commit.parse(hash));
    expect(worktree?.changed, isFalse);
  });

  test('a status with an entry past its headers has changed', () {
    final Worktree? worktree = readStatus(
      '# branch.oid $hash\x00# branch.head (detached)\x00'
      '1 .M N... 100644 100644 100644 $hash $hash lib/a.dart\x00',
    );
    expect(worktree?.changed, isTrue);
  });

  test('a status that names no commit at HEAD is no worktree', () {
    expect(readStatus('# branch.oid (initial)\x00'), isNull);
    expect(readStatus(''), isNull);
  });

  test('dart\'s version is the word after "Dart SDK version:"', () {
    expect(
      readSdkVersion(
        .dart,
        'Dart SDK version: 3.13.7 (stable) (Thu Oct 22) on "macos_arm64"\n',
      ),
      SdkVersion.parse('3.13.7'),
    );
    expect(readSdkVersion(.dart, 'no version here'), isNull);
  });

  test('flutter\'s version is frameworkVersion in its JSON, past any line '
      'before it', () {
    expect(
      readSdkVersion(
        .flutter,
        'Waiting for another flutter command...\n'
        '{"frameworkVersion": "3.47.9", "dartSdkVersion": "3.13.7"}\n',
      ),
      SdkVersion.parse('3.47.9'),
    );
    expect(readSdkVersion(.flutter, '{"channel": "stable"}'), isNull);
    expect(readSdkVersion(.flutter, '{not json}'), isNull);
    expect(readSdkVersion(.flutter, 'Dart SDK version: 3.13.7'), isNull);
  });

  test('a version is neither empty nor holds whitespace', () {
    expect(SdkVersion.parse(''), isNull);
    expect(SdkVersion.parse('3.13 .7'), isNull);
    expect(SdkVersion.parse('3.13.7-0.1.pre')?.version, '3.13.7-0.1.pre');
  });
}
