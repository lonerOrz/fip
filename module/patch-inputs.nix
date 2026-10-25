# Wires spec.nix to patch-tree.nix.
{
  unpatchedInputs,
  patchSpec,
  # Injected: this module does not know where the tools come from.
  runCommandLocal,
}:
let
  resolveSpec = import ./spec.nix;
  applyPatches = import ./apply-patches.nix { inherit runCommandLocal; };
  patchTree = import ./patch-tree.nix applyPatches;

  patchesByNarHash = resolveSpec unpatchedInputs patchSpec;

  patchedInputs = patchTree patchesByNarHash unpatchedInputs;
in
patchedInputs
// {
  self = unpatchedInputs.self // {
    inputs = patchedInputs;
  };
}
