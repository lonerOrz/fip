# Wires spec.nix to patch-tree.nix.
{
  unpatchedInputs,
  patchSpec,
  runCommandLocal,
  # Only a function spec uses this.
  pkgs ? null,
}:
let
  resolveSpec = import ./spec.nix;
  applyPatches = import ./apply-patches.nix { inherit runCommandLocal; };
  patchTree = import ./patch-tree.nix applyPatches;

  patchesByNarHash = resolveSpec { inherit unpatchedInputs patchSpec pkgs; };
in
# Returns the patched inputs without `self`; the entry point adds it.
patchTree patchesByNarHash unpatchedInputs
