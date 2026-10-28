# Shared by spec.nix and patch-tree.nix, which both gate on whether an input is
# a Flake. If they read `outputs` differently, one admits a tree the other
# refuses, a late and confusing error. The shared predicate keeps the two gates
# in lockstep.
input: builtins.hasAttr "outputs" input
