import 'package:muster/src/model/hosted_resolves.dart';
import 'package:test/test.dart';

void main() {
  test('a root resolves whether or not it holds its pubspec', () {
    expect(hostedResolves(.root, held: true), isTrue);
    expect(hostedResolves(.root, held: false), isTrue);
  });

  test('an example resolves only where it holds its pubspec', () {
    expect(hostedResolves(.example, held: true), isTrue);
    expect(hostedResolves(.example, held: false), isFalse);
  });
}
