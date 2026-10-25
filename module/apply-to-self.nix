# A function `patchSpec` is called once, with the consumer's inputs plus a
# `pkgs` alias, so a patch can be `pkgs.fetchpatch`.
{
  unpatchedInputs,
  patchSpec,
  buildPlatform ? null,
  pkgs ? null,
}:
let
  defaultPlatform =
    if buildPlatform != null then
      buildPlatform
    else if builtins ? currentSystem then
      builtins.currentSystem
    else
      "x86_64-linux";

  resolvedPkgs =
    if pkgs != null then
      pkgs
    else if unpatchedInputs ? nixpkgs then
      unpatchedInputs.nixpkgs.legacyPackages.${defaultPlatform}
    else
      throw (
        builtins.concatStringsSep "\n" [
          "fip: no package set to apply patches with"
          ""
          "Patching runs `patch` and coreutils in a derivation, so a package"
          "set is required. By default it is your own `nixpkgs` input at the"
          "build platform:"
          ""
          "  unpatchedInputs.nixpkgs.legacyPackages.${defaultPlatform}"
          ""
          "but the `unpatchedInputs` passed to `applyToInputs` has no `nixpkgs`."
          ""
          "Add a `nixpkgs` input, or pass a package set explicitly:"
          ""
          "  applyToInputs { inherit unpatchedInputs patchSpec; pkgs = <package set>; }"
        ]
      );

  resolvedSpec =
    if builtins.isFunction patchSpec then
      patchSpec (unpatchedInputs // { pkgs = resolvedPkgs; })
    else
      patchSpec;
in
unpatchedInputs
// (import ./patch-inputs.nix {
  inherit unpatchedInputs;
  patchSpec = resolvedSpec;
  inherit (resolvedPkgs) runCommandLocal;
})
