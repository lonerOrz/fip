# Public API, exposed as `patchLib`. Usage and the spec format are in README.md.
let
  applyToInputs = import ./module/apply-to-self.nix;
in
{
  # Returns `unpatchedInputs` with the patched sources swapped in.
  #
  # `pkgs` supplies `patch` and coreutils, defaulting to your own `nixpkgs`
  # input. `buildPlatform` only picks that default; pure eval hides the host's.
  inherit applyToInputs;

  # `{ <platform> = <patched>; }`. A patched source is built by the host, so a
  # flake serving hosts with different build platforms needs one entry each.
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

  # The engine, for callers wiring the stages themselves.
  patch = import ./module/patch-inputs.nix;
}
