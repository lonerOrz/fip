# Unit tests for `spec.nix`: tree + spec -> narHash -> [patches].
{ lib, patcherRoot }:

let
  resolveSpec = import "${patcherRoot}/module/spec.nix";
  validatePatch = import "${patcherRoot}/module/validate-patch.nix";

  # A derivation-shaped `pkgs.fetchpatch` result; distinct names so values differ.
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

  # Real files so the validator's existence branch runs on a usable path.
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

  resolve =
    inputs: spec:
    resolveSpec {
      unpatchedInputs = inputs;
      patchSpec = spec;
    };
  tryResolve = inputs: spec: builtins.tryEval (builtins.deepSeq (resolve inputs spec) true);

  throws = inputs: spec: !(tryResolve inputs spec).success;

  got = resolve tree {
    dep.patches = [ p1 ];
    dep.inputs.sub.patches = [ p2 ];
  };

  # `./p1.patch` in the fixture is the same path as `p1Path`.
  fromFile = resolve tree ./fixtures/spec-as-file.nix;
  fileEquivalent = resolve tree { dep.patches = [ p1Path ]; };
  fromFunctionFileThrows = throws tree ./fixtures/spec-as-function.nix;
  # A string is not carried into the store, so it is rejected.
  stringSpecThrows = throws tree "./fixtures/spec-as-file.nix";
  # The call lives in `resolveSpec`, so every entry point shares it.
  fromFunctionFile = resolveSpec {
    unpatchedInputs = tree;
    patchSpec = ./fixtures/spec-as-function.nix;
    pkgs = { };
  };
  fromFunctionFileEquivalent = resolve tree { dep.patches = [ p1Path ]; };

  aliased = resolve treeWithAlias {
    dep.inputs.sub.patches = [ p2 ];
    alias.patches = [ p2 ];
  };

  aliasedConflict = throws treeWithAlias {
    dep.inputs.sub.patches = [ p2 ];
    alias.patches = [ p3 ];
  };

  # Order is not significant.
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

  # Asserted as data: the exact problem strings, not a thrown message.
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

# A spec path is imported and resolves exactly like the equivalent attrset.
++ lib.optional (
  fromFile != fileEquivalent
) "spec: a path spec is imported and resolves identically"
++ lib.optional (!fromFunctionFileThrows) "spec: a function spec file makes resolveSpec throw"
++ lib.optional (!stringSpecThrows) "spec: a string spec is rejected, not walked as an attrset"
++ lib.optional (
  fromFunctionFile != fromFunctionFileEquivalent
) "spec: a function spec resolves when given a package set"

++ lib.optional (
  (aliased.${b} or [ ]) != [ p2 ]
) "spec: identical patches from two positions dedupe"
++ lib.optional (!aliasedConflict) "spec: conflicting patches from two positions must error"

# Order is not a conflict.
++ lib.optional (!aliasedReorderedOk) "spec: same patches in different order are not a conflict"

# The problem must name the missing file.
++ lib.optional (
  problemsMissing == [ ] || !(problemsContain "does-not-exist.patch" problemsMissing)
) "spec: missing patch file is reported and names the file"
++ lib.optional (
  !(problemsContain "At: dep" problemsMissing)
) "spec: missing patch file problem names the spec location"

# The problem must name the bad value's type.
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

# A bad patch throws; a good one does not.
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
