# A function spec: `resolveSpec` must reject it without a package set.
{ pkgs, ... }:

{
  dep.patches = [ ./p1.patch ];
}
