# A function spec for `generate`, equivalent to the inline attrset.
{ pkgs, ... }:

{
  systems.patches = [ ../../systems.patch ];
}
