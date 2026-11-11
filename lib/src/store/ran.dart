/// What a process that ran left: the [exitCode] it exited with, and what it
/// wrote to [stdout] and [stderr].
typedef Ran = ({int exitCode, String stdout, String stderr});
