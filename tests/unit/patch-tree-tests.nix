# Unit tests for `module/patch-tree.nix`: tree + patches -> patched tree
#
# Patching `systems` at the root must also patch the copy `dep1` reaches
# through `follows`. The fixture flakes are imported, so they must exist.
{
  lib,
  patcherRoot,
  fixtures,
  runCommandLocal,
}:

let
  applyPatches = import "${patcherRoot}/module/apply-patches.nix" { inherit runCommandLocal; };
  patchTree = import "${patcherRoot}/module/patch-tree.nix" applyPatches;

  hash = ch: "sha256-${lib.concatStringsSep "" (lib.replicate 43 ch)}=";
  sysHash = hash "s";
  subHash = hash "u";
  depHash = hash "d";

  systemsPatch = "${fixtures}/systems.patch";

  # Mirrors what Nix hands `outputs` for the fixture flakes.
  flake = narHash: outPath: inputs: {
    _type = "flake";
    inherit narHash inputs;
    outPath = outPath;
    outputs = { };
  };

  # dep1 declares inputs `systems` and `subdirFlake`; the test flake makes both
  # of them `follows`, so the SAME attrset appears at two positions.
  systemsNode = flake sysHash "${fixtures}/systems" { };
  subdirNode = flake subHash "${fixtures}/subdirFlake" { };

  tree = {
    self = {
      outPath = "${fixtures}/self";
    };
    systems = systemsNode;
    subdirFlake = subdirNode;
    dep1 = flake depHash "${fixtures}/dep1" {
      # `follows systems`: literally the same value.
      systems = systemsNode;
      subdirFlake = subdirNode;
    };
  };

  # Patch the shared source once, at the root position only.
  patched = patchTree { ${sysHash} = [ systemsPatch ]; } tree;

  untouched = patchTree { } tree;
in
[ ]
# `lib.optional COND MSG` emits MSG -- a failure -- when COND is TRUE, so each
# condition below is the NEGATION of the property being asserted.

++ lib.optional (untouched.dep1 != tree.dep1) "tree: unpatched node is the identical value"
++ lib.optional (untouched.systems != tree.systems) "tree: unpatched leaf is the identical value"
++ lib.optional (untouched ? "self") "tree: self must not appear in the result"

++ lib.optional (
  patched.systems.outPath == tree.systems.outPath
) "tree: patched source gets a new outPath"
++ lib.optional (
  patched.dep1.inputs.systems.outPath == tree.dep1.inputs.systems.outPath
) "tree: the SAME source is patched under its second position too"

++ lib.optional (
  patched.systems.value or null != "you've been patched!"
) "tree: patched flake is re-evaluated"
++ lib.optional (
  patched.dep1.directAccessSystem or null != "you've been patched!"
) "tree: patched child is visible to the parent's outputs"

++ lib.optional (patched.dep1 == tree.dep1) "tree: a parent of a patched node is re-imported"
++ lib.optional (
  patched.dep1.outPath != tree.dep1.outPath
) "tree: a re-imported-but-unpatched parent keeps its own source"
