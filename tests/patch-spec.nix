# Externalized patch spec for the test suite. Read by `applyToSelf` from
# <flake-root>/patch-spec.nix by convention. This mirrors how a consumer keeps
# their patch spec in its own file so a lifecycle workflow can add/remove
# entries without editing `flake.nix`.
#
# Written as a function `{ pkgs, ... }:` to prove the "want a param" path works
# (a `pkgs` alias for the build machine's nixpkgs is injected, so
# `pkgs.fetchpatch` is available for remote patches). Only local file paths are
# used here. `systems` and `subdirFlake` are *followed* from `dep1`, so they are
# patched at the root level (where they are declared directly). `dep1` is
# patched directly.
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
