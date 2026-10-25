# Applies patches to a source with `runCommandLocal`. Each patch file is a
# derivation input so the sandbox can read it.
{ runCommandLocal }:

{
  name,
  patches,
  src,
}:
runCommandLocal name { inherit patches; } ''
  cp -r "${src}/." "$out/"
  chmod -R u+w "$out"
  cd "$out"
  for p in $patches; do
    patch -p1 --no-backup-if-mismatch < "$p"
  done
''
