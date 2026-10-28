# Public API, exposed as `patchLib`.
let
  patchInputs = import ./module/apply-to-self.nix;
  generateWrapper = import ./generate.nix;
in
{
  # In-eval: `unpatchedInputs` with the patched sources swapped in.
  inherit patchInputs;

  # `{ <platform> = <patched>; }`, one entry per build platform.
  forSystemAttrs =
    {
      unpatchedInputs,
      platforms,
      patchSpec,
      pkgs ? null,
    }:
    builtins.listToAttrs (
      builtins.map (platform: {
        name = platform;
        value = patchInputs {
          inherit unpatchedInputs patchSpec pkgs;
          buildPlatform = platform;
        };
      }) platforms
    );

  # Engine: the patched inputs without `self`.
  patchTree = import ./module/patch-inputs.nix;

  # Pre-eval: realises the patched sources outside eval and emits a wrapper flake.
  inherit generateWrapper;
}
