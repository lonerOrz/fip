# Applies patches to a source via `runCommandLocal`.
{ runCommandLocal }:
let
  # Exposed so a test runs the exact script. `${p}` (not `toString p`) makes Nix
  # materialise the patch into the sandbox; `$out` is a single dollar.
  builder = patches: src: ''
    # Own the fail-fast so the error names the conflicted patch.
    set -euo pipefail

    cp -r "${src}/." "$out/"
    chmod -R u+w "$out"
    cd "$out"
    patches_arr=( ${builtins.concatStringsSep " " (map (p: "'${p}'") patches)} )
    for p in "''${patches_arr[@]}"; do
      if ! patch -p1 --no-backup-if-mismatch < "$p"; then
        echo "apply-patches: patch failed to apply: $p" >&2
        exit 1
      fi
    done
  '';

  apply =
    {
      name,
      patches,
      src,
    }:
    runCommandLocal name { inherit patches; } (builder patches src);
in
# Callable as `applyPatches { ... }`; `builder` is exposed for tests.
{
  __functor = _self: apply;
  inherit builder apply;
}
