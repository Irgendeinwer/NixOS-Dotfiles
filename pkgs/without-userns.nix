{
  libseccomp,
  runCommandCC,
}:
runCommandCC "without-userns"
  {
    buildInputs = [ libseccomp ];
  }
  ''
    mkdir -p "$out/bin"
    "$CC" -O2 -Wall -Wextra -Werror ${./without-userns.c} -lseccomp -o "$out/bin/without-userns"
  ''
