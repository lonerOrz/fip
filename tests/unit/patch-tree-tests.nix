# Unit tests for `patch-tree.nix`: tree + patches -> patched tree.
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

  # The same attrset appears at two positions.
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

  # A patch whose content is unreadable at eval time still forces a re-import.
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
  # A top-level alias: memoisation collapses all three positions to one.
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
# Each condition below is the negation of the property asserted.

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
# A derivation patch still forces a re-import.
++ lib.optional (
  patchedDrv.systemsDrv.value or null != "patched-by-derivation"
) "tree: a derivation patch forces re-import of a .nix file"
# All three positions (root, `follows`, alias) must share one derivation;
# per-position re-import would give them different names and outPaths.
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
++ lib.optional (
  !builtins.all (k: builtins.hasAttr k patched3.dep1) (builtins.attrNames tree.dep1)
) "no-impact: reconstructed node keeps all original attrs"
++ lib.optional (
  patched3.dep1 ? sourceInfo
) "no-impact: child-only node carries no audit sourceInfo"
++ lib.optional (
  untouched != builtins.removeAttrs tree [ "self" ]
) "regression: empty-patch deep no-impact"
++ lib.optional (
  patched.systems.sourceInfo.baseNarHash or null != sysHash
) "audit: own-patched node records baseNarHash"
++ lib.optional (
  patched.systems.sourceInfo.fipPatches or null != [ systemsPatch ]
) "audit: own-patched node records fipPatches"
