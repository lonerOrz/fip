# Unit tests for `module/spec.nix`: tree + spec -> narHash -> [patches].
# Pure: no fetches, IFD, or network.
{ lib, patcherRoot }:

let
  resolveSpec = import "${patcherRoot}/module/spec.nix";
  validatePatch = import "${patcherRoot}/module/validate-patch.nix";

  # A derivation-shaped value standing in for a `pkgs.fetchpatch` result; the
  # validator accepts derivations without touching disk. Names are distinct so
  # two patches are genuinely different values (needed for the conflict test).
  fetch = name: {
    _type = "derivation";
    type = "derivation";
    name = "fetched-${name}.patch";
    outPath = "/nix/store/${name}-fetched.patch";
    outputName = "out";
    drvPath = "/nix/store/${name}-fetched.drv";
  };
  p1 = fetch "p1";
  p2 = fetch "p2";
  p3 = fetch "p3";

  # Real files on disk (under tests/unit/fixtures/) so the validator's
  # path-existence branch runs on a usable path, not just derivations.
  p1Path = ./fixtures/p1.patch;

  # A path that does not exist on disk, for the missing-file test.
  missingPath = ./fixtures/does-not-exist.patch;

  hash = ch: "sha256-${lib.concatStringsSep "" (lib.replicate 43 ch)}=";
  a = hash "a";
  b = hash "b";
  c = hash "c";

  flake = narHash: outPath: inputs: {
    _type = "flake";
    inherit narHash inputs;
    outPath = "/nix/store/${outPath}-source";
    outputs = { };
  };

  # A non-Flake (`flake = false`) source: no `outputs`, no `inputs`.
  bare = narHash: outPath: {
    inherit narHash;
    outPath = "/nix/store/${outPath}-source";
  };
  # `alias` is the same attrset as `dep.sub`, standing in for a `follows`.
  tree = {
    self = {
      outPath = "/nix/store/self-source";
    };
    dep = flake a "dep" {
      sub = flake b "dep-sub" { };
      bare = bare c "dep-bare";
    };
    other = flake c "other" { };
  };

  treeWithAlias = tree // {
    alias = tree.dep.inputs.sub;
  };

  tryResolve = inputs: spec: builtins.tryEval (builtins.deepSeq (resolveSpec inputs spec) true);

  throws = inputs: spec: !(tryResolve inputs spec).success;

  got = resolveSpec tree {
    dep.patches = [ p1 ];
    dep.inputs.sub.patches = [ p2 ];
  };

  aliased = resolveSpec treeWithAlias {
    dep.inputs.sub.patches = [ p2 ];
    alias.patches = [ p2 ];
  };

  aliasedConflict = throws treeWithAlias {
    dep.inputs.sub.patches = [ p2 ];
    alias.patches = [ p3 ];
  };

  # The same source patched from two positions with the same patches in a
  # different order must not error: order is not significant.
  aliasedReorderedOk =
    !(throws treeWithAlias {
      dep.inputs.sub.patches = [
        p2
        p3
      ];
      alias.patches = [
        p3
        p2
      ];
    });

  # The validator's output, asserted as real data: each entry is the exact
  # problem string, so the test checks the wording rather than a thrown message.
  problemsMissing = validatePatch "dep" [ missingPath ];
  problemsNumber = validatePatch "dep" [ 42 ];
  problemsString = validatePatch "dep" [ "just-a-string" ];
  problemsClean = validatePatch "dep" [
    p1
    p1Path
  ];

  problemsContain = needle: hay: lib.any (msg: lib.hasInfix needle msg) hay;
in
# Assertions
[ ]
++ lib.optional (!(got ? ${a})) "spec: direct dependency keyed by narHash"
++ lib.optional (!(got ? ${b})) "spec: transitive dependency keyed by narHash"
++ lib.optional (got ? ${c}) "spec: an untouched sibling is absent"
++ lib.optional ((got.${a} or [ ]) != [ p1 ]) "spec: direct patches recorded"
++ lib.optional ((got.${b} or [ ]) != [ p2 ]) "spec: transitive patches recorded"

++ lib.optional (
  (aliased.${b} or [ ]) != [ p2 ]
) "spec: identical patches from two positions dedupe"
++ lib.optional (!aliasedConflict) "spec: conflicting patches from two positions must error"

# The same source patched from two positions with the same patches in a
# different order must not be treated as a conflict.
++ lib.optional (!aliasedReorderedOk) "spec: same patches in different order are not a conflict"

# A missing local patch file must be rejected and the problem string must name
# the file. Asserted on the validator's returned data, not a thrown message.
++ lib.optional (
  problemsMissing == [ ] || !(problemsContain "does-not-exist.patch" problemsMissing)
) "spec: missing patch file is reported and names the file"
++ lib.optional (
  !(problemsContain "At: dep" problemsMissing)
) "spec: missing patch file problem names the spec location"

# A patch that is neither a path nor a derivation must be rejected, and the
# problem string must name the bad value's type.
++ lib.optional (
  problemsNumber == [ ] || !(problemsContain "Got: int" problemsNumber)
) "spec: a non-path non-derivation patch is reported and names its type"
++ lib.optional (
  !(problemsContain "At: dep" problemsNumber)
) "spec: bad patch problem names the spec location"
++ lib.optional (
  problemsString == [ ] || !(problemsContain "Got: string" problemsString)
) "spec: a string patch is reported and names its type"

# The validator must accept the usable kinds: a derivation and an existing path.
++ lib.optional (
  problemsClean != [ ]
) "spec: a derivation and an existing path are accepted (no problems)"

# resolveSpec must throw on a bad patch (the validator's problems are surfaced
# as an error) while accepting good patches.
++ lib.optional (
  !(throws tree { dep.patches = [ missingPath ]; })
) "spec: a missing local patch file makes resolveSpec throw"
++ lib.optional (
  !(throws tree { dep.patches = [ 42 ]; })
) "spec: a non-path non-derivation patch makes resolveSpec throw"
++ lib.optional (
  !(throws tree { dep.inputs.nope.patches = [ p1 ]; })
) "spec: patching a non-existent input must error"
++ lib.optional (
  !(throws tree { dep.inputs.bare.patches = [ p1 ]; })
) "spec: patching a non-Flake input must error"
++ lib.optional (throws tree {
  dep.patches = [ ];
}) "spec: an empty patch list is a no-op, not an error"
++ lib.optional (
  (throws tree { dep.patches = [ p1 ]; })
) "spec: a derivation patch must be accepted (not rejected)"
