# Applies patches to a source via `runCommandLocal`. Each patch file is passed
# as a derivation input so the sandbox can read it.
{ runCommandLocal }:
let
  # The builder as text, exposed as `builder` so a test runs the exact script
  # the library uses (not a copy) and observes its exit status and stderr.
  # `$out` uses a single dollar because Nix would otherwise interpolate it as a
  # Nix variable; `${src}` is the Nix-level source argument.
  #
  # The patch list is interpolated as a quoted shell array, so the script is
  # self-contained: it applies exactly the patches it is given and never reads
  # an ambient `$patches`. Each path uses Nix's `${p}`, not `toString p`: Nix
  # rewrites `${p}` to the store path materialised in the sandbox, whereas
  # `toString` emits the source-tree copy, which is absent from the sandbox
  # closure and would 404. `patches` also rides along as the derivation input in
  # `apply`, so the sandbox closure contains the files.
  builder = patches: src: ''
    # The loop's exit status is only the last patch's, and the inherited `set -e`
    # aborts on the first failing patch only by accident, not by contract. We
    # therefore own the fail-fast and name the culprit, so the error points at
    # the conflicted patch rather than a generic non-zero exit.
    set -euo pipefail

    cp -r "${src}/." "$out/"
    chmod -R u+w "$out"
    cd "$out"
    patches_arr=( ${builtins.concatStringsSep " " (map (p: "'${p}'") patches)} )
    for p in "''${patches_arr[@]}"; do
      # `patch` exits non-zero on a failed hunk; name the culprit so the error
      # points at the conflicted patch, not a later unrelated one.
      if ! patch -p1 --no-backup-if-mismatch < "$p"; then
        echo "apply-patches: patch failed to apply: $p" >&2
        exit 1
      fi
    done
  '';

  # `applyPatches { name, patches, src }` builds the patched source.
  apply =
    {
      name,
      patches,
      src,
    }:
    runCommandLocal name { inherit patches; } (builder patches src);
in
# Callable as `applyPatches { ... }` and inspectable: the exported `builder` lets
# a test run the exact script. `__functor` makes the attrset callable as `apply`.
{
  __functor = _self: apply;
  inherit builder apply;
}
