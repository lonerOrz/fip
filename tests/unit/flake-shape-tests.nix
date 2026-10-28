# Unit tests for the shared Flake predicate.
{ lib, patcherRoot }:

let
  isFlake = import "${patcherRoot}/module/flake-shape.nix";

  # Nix hands `outputs` on every importable flake.
  flakeInput = {
    _type = "flake";
    narHash = "sha256-...";
    outPath = "/nix/store/flake-source";
    outputs = { };
    inputs = { };
  };

  # A non-Flake source (`flake = false`): no `outputs` attribute at all.
  nonFlakeSource = {
    narHash = "sha256-...";
    outPath = "/nix/store/bare-source";
  };

  # `outputs` present but empty is still a Flake: `hasAttr` ignores the value.
  emptyOutputs = {
    _type = "flake";
    narHash = "sha256-...";
    outPath = "/nix/store/empty-source";
    outputs = { };
  };
in
[ ]
# Assert the exact boolean, not just truthiness.
++ lib.optional (isFlake flakeInput != true) "flake-shape: a Flake input is recognised"
++ lib.optional (isFlake nonFlakeSource != false) "flake-shape: a non-Flake source is not a Flake"
++ lib.optional (
  isFlake emptyOutputs != true
) "flake-shape: an input with empty outputs is still a Flake"
