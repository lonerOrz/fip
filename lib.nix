# Public API, exposed as `patchLib`.
let
  applyToInputs = import ./module/apply-to-self.nix;
in
{
  # Returns `unpatchedInputs` with the patched sources swapped in.
  #
  # `pkgs` supplies `patch` and coreutils; it defaults to your `nixpkgs` input.
  # `buildPlatform` only chooses that default, since pure eval hides the host.
  inherit applyToInputs;

  # `{ <platform> = <patched>; }`. Each entry is built by the host, so a flake
  # serving hosts with different build platforms needs one entry per platform.
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
        value = applyToInputs {
          inherit unpatchedInputs patchSpec pkgs;
          buildPlatform = platform;
        };
      }) platforms
    );

  # The engine: a pure tree transform returning only the patched inputs, without
  # `self`, for callers wiring the stages themselves.
  patch = import ./module/patch-inputs.nix;
}
