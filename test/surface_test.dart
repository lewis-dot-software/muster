import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/loads.dart';

/// The types [type] names, each type argument, parameter, return, field and
/// alias among them, whatever their library.
Set<Element> _named(DartType type) => {
  if (type.alias case final InstantiatedTypeAliasElement alias) ...{
    alias.element,
    ...alias.typeArguments.expand(_named),
  },
  ...switch (type) {
    InterfaceType(:final InterfaceElement element, :final typeArguments) => {
      element,
      ...typeArguments.expand(_named),
    },
    FunctionType(
      :final DartType returnType,
      :final List<FormalParameterElement> formalParameters,
    ) =>
      {
        ..._named(returnType),
        for (final FormalParameterElement parameter in formalParameters)
          ..._named(parameter.type),
      },
    RecordType(:final positionalFields, :final namedFields) => {
      for (final RecordTypeField field in [...positionalFields, ...namedFields])
        ..._named(field.type),
    },
    TypeParameterType(:final DartType bound) => _named(bound),
    DynamicType() || VoidType() || NeverType() || InvalidType() => const {},
    _ => throw StateError('a type the walk does not know: $type'),
  },
};

/// Each public member of [element] beside the types its signature names,
/// and a type's supertypes beside it.
Map<String, Set<Element>> _members(Element element) => switch (element) {
  InterfaceElement() => {
    '${element.name}: its supertypes': {
      for (final InterfaceType supertype in [
        ?element.supertype,
        ...element.interfaces,
        ...element.mixins,
      ])
        ..._named(supertype),
    },
    for (final ExecutableElement member in [
      ...element.constructors,
      ...element.getters,
      ...element.setters,
      ...element.methods,
    ])
      if (member.isPublic)
        '${element.name}.${member.name ?? 'new'}': _named(member.type),
  },
  TypeAliasElement(:final DartType aliasedType) => {
    element.name!: _named(aliasedType),
  },
  ExecutableElement(:final FunctionType type) => {element.name!: _named(type)},
  TopLevelVariableElement(:final DartType type) => {
    element.name!: _named(type),
  },
  _ => throw StateError('an export the walk does not know: $element'),
};

void main() {
  test('Every type a public member of the library names is exported by '
      '`lib/muster.dart`.', () async {
    final String library = p.join(await musterRoot(), 'lib', 'muster.dart');
    final AnalysisContextCollection contexts = .new(
      includedPaths: [p.normalize(library)],
    );
    final SomeResolvedLibraryResult resolved = await contexts
        .contextFor(library)
        .currentSession
        .getResolvedLibrary(p.normalize(library));
    final LibraryElement surface = switch (resolved) {
      ResolvedLibraryResult(:final LibraryElement element) => element,
      _ => fail('lib/muster.dart did not resolve: $resolved'),
    };
    final Set<Element> exported = {
      ...surface.exportNamespace.definedNames2.values,
    };
    expect(exported, isNotEmpty);
    final Map<String, List<String>> unexported = {
      for (final Element element in exported)
        for (final MapEntry<String, Set<Element>>(:key, :value) in _members(
          element,
        ).entries)
          if ([
                for (final Element named in value)
                  if ((named.library?.uri.toString() ?? '').startsWith(
                        'package:muster/',
                      ) &&
                      !exported.contains(named))
                    named.name!,
              ]
              case final List<String> names when names.isNotEmpty)
            key: names..sort(),
    };
    expect(unexported, isEmpty);
  });
}
