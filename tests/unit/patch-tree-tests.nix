# Unit tests for `module/patch-tree.nix`: tree + patches -> patched tree.
# Patching `systems` at the root must also patch the copy `dep1` reaches through
# `follows`; fixtures are imported, so they must exist.
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

  # `dep1` follows `systems` and `subdirFlake`, so the same attrset appears at
  # two positions.
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

  # A patch whose content cannot be inspected at eval time (a `pkgs.fetchpatch`
  # result) must still force a re-import, so the .nix file it changes is the one
  # evaluated. The derivation edits `default.nix`.
  drvHash = hash "v";
  systemsDrvNode = flake drvHash "${fixtures}/systems" { };
  drvPatch = runCommandLocal "simulated-fetchpatch-derivation.patch" { } ''
    cat > "$out" <<'EOF'
    --- a/default.nix
    +++ b/default.nix
    @@ -1 +1 @@
    -"x86_64-linux"
    +"patched-by-derivation"
    EOF
  '';
  treeDrv = tree // {
    systemsDrv = systemsDrvNode;
  };
  patchedDrv = patchTree { ${drvHash} = [ drvPatch ]; } treeDrv;

  untouched = patchTree { } tree;
  # A third position for the shared patched source: a top-level alias of the
  # same `systems` node under a different attribute name. Memoization by narHash
  # collapses all three to one derivation.
  tree3 = tree // {
    systemsCopy = systemsNode;
  };
  patched3 = patchTree { ${sysHash} = [ systemsPatch ]; } tree3;
  # The single derivation the memo must reuse for every position of `systems`.
  systemsPatchedOut =
    (applyPatches {
      name = "${sysHash}-patched";
      patches = [ systemsPatch ];
      src = systemsNode.outPath;
    }).outPath;
in
[ ]
# `lib.optional COND MSG` emits MSG (a failure) when COND is true, so each
# condition below is the negation of the property being asserted.

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
# A derivation patch whose content cannot be read at eval time still forces a
# re-import, so the .nix file it edits is the one evaluated.
++ lib.optional (
  patchedDrv.systemsDrv.value or null != "patched-by-derivation"
) "tree: a derivation patch forces re-import of a .nix file"
# Memoization: `systems` is patched but reached from three positions (root,
# `dep1.inputs.systems` via follows, and `systemsCopy`). After the rewrite each
# distinct source is re-imported exactly once, so all three positions share the
# same patched derivation. Under the old per-position code the `systemsCopy`
# position carried a different derivation name and outPath, so this guard fails
# on regression to per-position re-import.
++ lib.optional (
  patched3.systems.outPath != patched3.systemsCopy.outPath
) "memo: systems shared between two top-level positions"
++ lib.optional (
  patched3.systems.outPath != patched3.dep1.inputs.systems.outPath
) "memo: systems shared between root and dep1 positions"
++ lib.optional (
  patched3.systemsCopy.outPath != patched3.dep1.inputs.systems.outPath
) "memo: systems shared between copy and dep1 positions"
++ lib.optional (
  patched3.systems.outPath != systemsPatchedOut
) "memo: systems equals the single memoized patched derivation"
