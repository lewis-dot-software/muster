/// [text] quoted for a POSIX shell, as one word whatever it holds.
String shellQuoted(String text) => "'${text.replaceAll("'", r"'\''")}'";
