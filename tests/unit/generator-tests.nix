# Checks that the patch applier accepts a local patch file and a patch
# derivation (what `pkgs.fetchpatch` produces), and that the patch lands.
#
# Reading the built output forces realisation, so this builds two small
# derivations and needs no network.
{
  lib,
  patcherRoot,
  fixtures,
  runCommandLocal,
}:

let
  applyPatches = import "${patcherRoot}/module/apply-patches.nix" { inherit runCommandLocal; };

  patchDerivation = runCommandLocal "simulated-fetchpatch.patch" { } ''
    cat > "$out" <<'EOF'
    --- a/value.nix
    +++ b/value.nix
    @@ -1 +1 @@
    -"original"
    +"patched via derivation"
    EOF
  '';

  fromFile = applyPatches {
    name = "patched-from-file";
    patches = [ "${fixtures}/dep1-int-to-str.patch" ];
    src = "${fixtures}/dep1";
  };

  fromDerivation = applyPatches {
    name = "patched-from-derivation";
    patches = [ patchDerivation ];
    src = "${fixtures}/dep1";
  };
in
[ ]
++ lib.optional (
  !(lib.hasInfix "you've been patched!" (builtins.readFile (fromFile + "/value.nix")))
) "generator: local patch is applied"
++ lib.optional (
  !(lib.hasInfix "patched via derivation" (builtins.readFile (fromDerivation + "/value.nix")))
) "generator: patch derivation is applied"
