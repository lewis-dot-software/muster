import 'package:muster/src/model/manifest_sought.dart';
import 'package:muster/src/model/os.dart';
import 'package:muster/src/model/seek_manifests.dart';
import 'package:test/test.dart';

/// The manifests a load at `/c` sought, from the working directory `/w`.
List<ManifestSought> _sought(
  List<String> named, {
  String? variable,
  Os os = .posix,
  String root = '/c',
  String workingDirectory = '/w',
}) => seekManifests(
  named,
  (variables: {'MUSTER_MANIFESTS': ?variable}, os: os),
  .new(root, os),
  .new(workingDirectory, os),
);

void main() {
  test("with none named, the root's muster.yaml comes first, unnamed, then "
      'each MUSTER_MANIFESTS lists, in its order', () {
    expect(_sought([], variable: '/m/a.yaml:b/c.yaml'), [
      (path: '/c/muster.yaml', named: false),
      (path: '/m/a.yaml', named: true),
      (path: '/w/b/c.yaml', named: true),
    ]);
  });

  test('with none named and MUSTER_MANIFESTS unset, the root\'s muster.yaml '
      'is sought alone', () {
    expect(_sought([]), [(path: '/c/muster.yaml', named: false)]);
  });

  test('an empty entry in MUSTER_MANIFESTS is passed over', () {
    expect(_sought([], variable: '::/m/a.yaml:'), [
      (path: '/c/muster.yaml', named: false),
      (path: '/m/a.yaml', named: true),
    ]);
  });

  test("manifests named replace both the root's muster.yaml and "
      'MUSTER_MANIFESTS, each read against the working directory', () {
    expect(
      _sought(['a.yaml', '../x/./b.yaml', '/m/c.yaml'], variable: '/v.yaml'),
      [
        (path: '/w/a.yaml', named: true),
        (path: '/x/b.yaml', named: true),
        (path: '/m/c.yaml', named: true),
      ],
    );
  });

  test('on Windows MUSTER_MANIFESTS splits on ;, since its paths hold :', () {
    expect(
      _sought(
        [],
        variable: r'C:\m\a.yaml;b.yaml',
        os: .windows,
        root: r'C:\c',
        workingDirectory: r'C:\w',
      ),
      [
        (path: r'C:\c\muster.yaml', named: false),
        (path: r'C:\m\a.yaml', named: true),
        (path: r'C:\w\b.yaml', named: true),
      ],
    );
  });
}
