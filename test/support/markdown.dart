/// A fenced block of markdown:
///
/// - `language`: the word after its opening fence, empty where none is.
/// - `code`: the lines between its fences.
typedef FencedBlock = ({String language, String code});

/// A fenced block of markdown, its language and its code captured.
final RegExp _fence = .new(
  r'^```(\w*)[^\n]*\n(.*?)^```',
  multiLine: true,
  dotAll: true,
);

/// Each fenced block of [markdown], in order.
List<FencedBlock> fencedBlocks(String markdown) => [
  for (final RegExpMatch fence in _fence.allMatches(markdown))
    (language: fence[1]!, code: fence[2]!),
];

/// [markdown] with each fenced block cut out.
String outsideFences(String markdown) => markdown.replaceAll(_fence, '');
