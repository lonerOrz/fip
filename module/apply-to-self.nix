# In-eval: the patched inputs with `self.inputs` set to them.
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
          "but the `unpatchedInputs` passed to `patchInputs` has no `nixpkgs`."
          ""
          "Add a `nixpkgs` input, or pass a package set explicitly:"
          ""
          "  patchInputs { inherit unpatchedInputs patchSpec; pkgs = <package set>; }"
        ]
      );

  patchedTree = import ./patch-inputs.nix {
    inherit unpatchedInputs patchSpec;
    # `resolveSpec` calls a function spec with this as `pkgs`.
    pkgs = resolvedPkgs;
    inherit (resolvedPkgs) runCommandLocal;
  };
in
patchedTree
// {
  self = unpatchedInputs.self // {
    inputs = patchedTree;
  };
}
