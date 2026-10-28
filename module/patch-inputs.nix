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
in
# Pure tree transform: returns `unpatchedInputs` with the patched sources swapped
# in and no `self`. Assembling `self` is the entry point's job, not the engine's.
patchTree patchesByNarHash unpatchedInputs
