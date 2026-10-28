# Test spec in its own file, as a consumer would keep one. A function, to prove
# the injected `pkgs` alias reaches `pkgs.fetchpatch`.
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
