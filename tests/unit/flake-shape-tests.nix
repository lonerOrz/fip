# Unit tests for the shared "is this a Flake input?" predicate.
# `spec.nix` and `patch-tree.nix` both gate on `outputs`; this shared definition
# keeps the two decisions from disagreeing. Pure: no fetches, no IFD.
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

  # An input with `outputs` present but empty is still a Flake, because the
  # attribute is present; `hasAttr` does not care about the value.
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
