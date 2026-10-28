# Happy-path behaviour: a patch whose context matches must land, and the realised
# output must contain the patched value (asserted on its output, not source text).
#
# The fail-fast property -- a patch that does not apply must fail the build and
# name the culprit -- is asserted by the `apply-patches-fail-fast` derivation
# below. The builder (`builder`) is exported, so the test runs the exact script
# the library uses, not a copy, and observes its exit status and stderr. The
# exported builder is self-contained: it applies exactly the patches it is given
# and ignores any ambient `$patches`, which `apply-patches-no-ambient` asserts.
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
  # A patch that exists but whose context does not match `value.nix`: `patch`
  # exits non-zero, so the builder must fail the build and name the culprit. The
  # exported builder runs directly against a scratch $out so we observe the real
  # exit status and stderr; building this derivation is the assertion.
  nonmatchingPatch = "${fixtures}/unit/fixtures/nonmatching.patch";
  # The builder interpolates the patch list it is given, so the argument is the
  # only source of truth: no ambient `patches` env var to keep in sync. The exact
  # exported script runs unmodified against a scratch $out.
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
  # Self-consistency: the builder applies exactly the patches it is given and is
  # blind to any ambient `$patches`. Here we pass an empty list while exporting a
  # `$patches` that points at the nonmatching patch; a successful build proves the
  # builder is self-contained.
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
# `lib.optional COND MSG` emits MSG (a failure) when COND is true, so each
# condition below is the negation of the property being asserted.
++ lib.optional (
  !(lib.hasInfix "you've been patched!" (builtins.readFile (fromFile + "/value.nix")))
) "apply-patches: a matching patch is applied"
# Building `failFast` proves the nonmatching patch both fails the build and is
# named; if either property is missing the derivation fails to build.
++ lib.optional (
  !(builtins.pathExists failFast)
) "apply-patches: a nonmatching patch fails the build"
# Building `noAmbient` proves the builder is self-contained: with an empty
# argument it applies nothing even when `$patches` is set in the environment.
++ lib.optional (
  !(builtins.pathExists noAmbient)
) "apply-patches: builder is self-contained (ignores ambient \$patches)"
