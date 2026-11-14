import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/published_pubspec.dart';
import 'package:muster/src/model/read_published_pubspec.dart';
import 'package:muster/src/model/pubspec_overrides.dart';
import 'package:test/test.dart';

import '../support/hosted.dart';
import '../support/lines_printed.dart';

void main() {
  group('readPublishedPubspec', () {
    test('reads a member for a pubspec of `resolution: workspace` alone', () {
      expect(
        readPublishedPubspec('name: a\nresolution: workspace\n').member,
        isTrue,
      );
      expect(
        readPublishedPubspec('name: a\nresolution: external\n').member,
        isFalse,
      );
      expect(readPublishedPubspec('name: a\n').member, isFalse);
    });

    test('reads overrides for a pubspec holding `dependency_overrides`, '
        'empty or not', () {
      expect(
        readPublishedPubspec(
          'name: a\ndependency_overrides:\n  b:\n    path: ../b\n',
        ).overrides,
        isTrue,
      );
      expect(
        readPublishedPubspec('name: a\ndependency_overrides:\n').overrides,
        isTrue,
      );
      expect(readPublishedPubspec('name: a\n').overrides, isFalse);
    });

    test('reads neither from a pubspec that is no YAML map', () {
      for (final String pubspec in ['name: [a\n', '- workspace\n', '']) {
        expect(readPublishedPubspec(pubspec), (
          member: false,
          overrides: false,
        ));
      }
    });

    test(
      'reads past a directive the YAML reader warns of, printing nothing',
      () {
        late final PublishedPubspec published;
        expect(
          linesPrinted(
            () => published = readPublishedPubspec(
              '%FOO bar\n---\nname: a\nresolution: workspace\n',
            ),
          ),
          isEmpty,
        );
        expect(published.member, isTrue);
      },
    );
  });

  group('pubspecOverrides', () {
    /// Every pubspec a package may publish, by what muster reads of it.
    const List<PublishedPubspec> published = [
      (member: false, overrides: false),
      (member: false, overrides: true),
      (member: true, overrides: false),
      (member: true, overrides: true),
    ];

    test("a root resolved alone sets no resolution where it is a workspace's "
        'member, and no dependency overrides where its pubspec holds some', () {
      expect(
        [
          for (final PublishedPubspec published in published)
            pubspecOverrides(
              hostedOf('a'),
              .root,
              published: published,
              holding: false,
            ),
        ],
        [
          null,
          'dependency_overrides:\n',
          'resolution:\n',
          'resolution:\ndependency_overrides:\n',
        ],
      );
    });

    test('a root resolved as a dependency needs none, whatever its pubspec '
        'holds', () {
      for (final PublishedPubspec published in published) {
        expect(
          pubspecOverrides(
            hostedOf('a', resolution: .asDependency),
            .root,
            published: published,
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
        for (final PublishedPubspec published in published) {
          expect(
            pubspecOverrides(
              codebase,
              .example,
              published: published,
              holding: false,
            ),
            '${published.member ? 'resolution:\n' : ''}'
            'dependency_overrides:\n  a:\n    path: ..\n',
          );
        }
      }
    });

    test('a package holding one already needs none, whatever it is', () {
      for (final HostedCodebase codebase in [
        hostedOf('a'),
        hostedOf('a', resolution: .asDependency),
      ]) {
        for (final Package package in Package.values) {
          for (final PublishedPubspec published in published) {
            expect(
              pubspecOverrides(
                codebase,
                package,
                published: published,
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
