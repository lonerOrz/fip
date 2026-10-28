# A matching patch must land (asserted on the built output, not source text); a
# non-matching one must fail the build and name the culprit.
{
  lib,
  patcherRoot,
  fixtures,
  runCommandLocal,
}:

let
  applyPatches = import "${patcherRoot}/module/apply-patches.nix" { inherit runCommandLocal; };

  builder = applyPatches.builder;

  fromFile = applyPatches {
    name = "patched-from-file";
    patches = [ "${fixtures}/dep1-int-to-str.patch" ];
    src = "${fixtures}/dep1";
  };
  # A non-matching patch must fail the build and name the culprit.
  nonmatchingPatch = "${fixtures}/unit/fixtures/nonmatching.patch";
  # The argument is the only source of truth: no ambient `patches` to sync.
  failFast = runCommandLocal "apply-patches-fail-fast" { } ''
    work=$(mktemp -d)
    out_real="$out"
    export out="$work/out"; mkdir -p "$out"
    if bash -c ${
      lib.escapeShellArg (builder [ nonmatchingPatch ] "${fixtures}/dep1")
    } >"$work/log" 2>&1; then
      echo "FAILURE: the patch was expected not to apply, but it did" >&2; exit 1
    fi
    grep -q 'nonmatching.patch' "$work/log" || {
      echo "FAILURE: the error did not name the culprit patch" >&2
      cat "$work/log" >&2
      exit 1
    }
    echo ok > "$out_real"
  '';
  # Empty argument with `$patches` set: a successful build proves it is
  # self-contained.
  noAmbient = runCommandLocal "apply-patches-no-ambient" { } ''
    work=$(mktemp -d)
    out_real="$out"
    export out="$work/out"; mkdir -p "$out"
    export patches=${lib.escapeShellArg nonmatchingPatch}
    if ! bash -c ${lib.escapeShellArg (builder [ ] "${fixtures}/dep1")} >"$work/log" 2>&1; then
      echo "FAILURE: builder applied an ambient \$patches despite an empty argument" >&2
      cat "$work/log" >&2
      exit 1
    fi
    echo ok > "$out_real"
  '';
in
[ ]
# Each condition below is the negation of the property asserted.
++ lib.optional (
  !(lib.hasInfix "you've been patched!" (builtins.readFile (fromFile + "/value.nix")))
) "apply-patches: a matching patch is applied"
# Building it proves both properties; either one missing fails the build.
++ lib.optional (
  !(builtins.pathExists failFast)
) "apply-patches: a nonmatching patch fails the build"
# Proves the builder ignores an ambient `$patches`.
++ lib.optional (
  !(builtins.pathExists noAmbient)
) "apply-patches: builder is self-contained (ignores ambient \$patches)"
