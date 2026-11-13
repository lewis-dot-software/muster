import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/pubspec_overrides.dart';
import 'package:muster/src/model/workspace_member.dart';
import 'package:test/test.dart';

import '../support/hosted.dart';

void main() {
  group('workspaceMember', () {
    test('holds for a pubspec of `resolution: workspace` alone', () {
      expect(workspaceMember('name: a\nresolution: workspace\n'), isTrue);
      expect(workspaceMember('name: a\nresolution: external\n'), isFalse);
      expect(workspaceMember('name: a\n'), isFalse);
    });

    test('holds for no pubspec that is no YAML map', () {
      expect(workspaceMember('name: [a\n'), isFalse);
      expect(workspaceMember('- workspace\n'), isFalse);
      expect(workspaceMember(''), isFalse);
    });
  });

  group('pubspecOverrides', () {
    test("a root resolved alone sets no resolution where it is a workspace's "
        'member, and needs none where it is not', () {
      expect(
        pubspecOverrides(hostedOf('a'), .root, member: true, holding: false),
        'resolution:\n',
      );
      expect(
        pubspecOverrides(hostedOf('a'), .root, member: false, holding: false),
        isNull,
      );
    });

    test('a root resolved as a dependency needs none, member or not', () {
      for (final bool member in [true, false]) {
        expect(
          pubspecOverrides(
            hostedOf('a', resolution: .asDependency),
            .root,
            member: member,
            holding: false,
          ),
          isNull,
        );
      }
    });

    test('an example overrides the package to its own path under either '
        "resolution, and sets no resolution where it is a workspace's "
        'member', () {
      for (final HostedCodebase codebase in [
        hostedOf('a'),
        hostedOf('a', resolution: .asDependency),
      ]) {
        expect(
          pubspecOverrides(codebase, .example, member: false, holding: false),
          'dependency_overrides:\n  a:\n    path: ..\n',
        );
        expect(
          pubspecOverrides(codebase, .example, member: true, holding: false),
          'resolution:\ndependency_overrides:\n  a:\n    path: ..\n',
        );
      }
    });

    test('a package holding one already needs none, whatever it is', () {
      for (final HostedCodebase codebase in [
        hostedOf('a'),
        hostedOf('a', resolution: .asDependency),
      ]) {
        for (final Package package in Package.values) {
          for (final bool member in [true, false]) {
            expect(
              pubspecOverrides(
                codebase,
                package,
                member: member,
                holding: true,
              ),
              isNull,
            );
          }
        }
      }
    });
  });
}
