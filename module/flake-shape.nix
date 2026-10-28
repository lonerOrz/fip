# Shared so spec.nix and patch-tree.nix gate on the same predicate.
input: builtins.hasAttr "outputs" input
