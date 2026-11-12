/// How a reletting contender takes its claim first.
enum Take {
  /// By `holding`, which waits on a claim found held.
  waiting,

  /// By `holdingIfFree`, which tries it once.
  once,
}
