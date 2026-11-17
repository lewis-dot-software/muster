import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/loads.dart';

/// Gathers each record type a unit annotates bare, every one but the type a
/// `typedef` names and an extension type's representation, as the rule that
/// puts plain data in a record behind a `typedef` spares those alone.
final class _Bare extends RecursiveAstVisitor<void> {
  _Bare(this._file, this._unit);

  final String _file;
  final CompilationUnit _unit;

  /// Each bare record type, as its file, its line and its source.
  final List<String> found = [];

  @override
  void visitRecordTypeAnnotation(RecordTypeAnnotation node) {
    if (!_spared(node)) {
      final int line = _unit.lineInfo.getLocation(node.offset).lineNumber;
      found.add('$_file:$line ${node.toSource()}');
    }
    super.visitRecordTypeAnnotation(node);
  }
}

/// Whether [record] is the type a `typedef` names, or the type of an
/// extension type's representation.
bool _spared(RecordTypeAnnotation record) => switch (record.parent) {
  TypeAlias() => true,
  final FormalParameter parameter => _representation(parameter),
  _ => false,
};

/// Whether [parameter] is an extension type's representation, a parameter
/// in its declaration outside its body and outside any function type's.
bool _representation(FormalParameter parameter) {
  for (AstNode? at = parameter.parent?.parent; at != null; at = at.parent) {
    switch (at) {
      case ExtensionTypeDeclaration():
        return true;
      case TypeAnnotation() ||
          FormalParameter() ||
          FunctionBody() ||
          ClassMember() ||
          CompilationUnitMember():
        return false;
    }
  }
  return false;
}

void main() {
  test('No record type stands outside a `typedef` in `lib/` or `test/`, '
      "but an extension type's representation.", () async {
    final String root = await musterRoot();
    final List<String> bare = [];
    for (final String directory in ['lib', 'test']) {
      final List<File> files = [
        for (final FileSystemEntity entity in Directory(
          p.join(root, directory),
        ).listSync(recursive: true))
          if (entity case final File file when file.path.endsWith('.dart'))
            file,
      ];
      expect(files, isNotEmpty, reason: directory);
      for (final File file in files) {
        final CompilationUnit unit = parseString(
          content: file.readAsStringSync(),
          path: file.path,
        ).unit;
        final _Bare walk = .new(p.relative(file.path, from: root), unit);
        unit.accept(walk);
        bare.addAll(walk.found);
      }
    }
    expect(bare, isEmpty);
  });
}
