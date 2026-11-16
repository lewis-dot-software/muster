/// The smaller cases a property whose runs touch the disk or run a process
/// shrinks a failure through at most, its `shrinkSteps`, so a failure ends
/// after a bounded count of runs, however long each run takes.
const int gitShrinks = 20;
