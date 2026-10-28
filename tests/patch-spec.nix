# Externalized patch spec for the test suite, read from `<flake-root>/patch-spec.nix`
# by convention, mirroring how a consumer keeps its spec in its own file.
# Written as a function `{ pkgs, ... }:` to prove the injected `pkgs` alias makes
# `pkgs.fetchpatch` available. `systems` and `subdirFlake` are followed from
# `dep1`, so they are patched at the root level where they are declared directly.
{ pkgs, ... }:

{
  dep1.patches = [
    ./dep1-int-to-str.patch
    ./dep1-change-attrset.patch
  ];

  systems.patches = [
    ./systems.patch
  ];

  subdirFlake.patches = [
    ./new-file.patch
  ];
}
