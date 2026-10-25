# Rebuilds the tree, replacing every source that has patches. The `inputs`
# argument is already the resolved graph, so no lockfile is involved.
# `applyPatches` is injected: this knows a patched source differs, not how.
applyPatches:

# narHash -> [patches], from spec.nix.
patchesByNarHash:

unpatchedInputs:

let
  # Returns `{ result, patched }` so a parent can tell whether anything
  # beneath it changed without walking the subtree twice.
  rebuild =
    name: input:
    let
      narHash = input.narHash or null;
      ownPatches = if narHash == null then [ ] else patchesByNarHash.${narHash} or [ ];

      isFlake = builtins.hasAttr "outputs" input;

      kids = builtins.mapAttrs rebuild (input.inputs or { });
      anyChildPatched = builtins.any (k: k.patched) (builtins.attrValues kids);
      childValues = builtins.mapAttrs (_: k: k.result) kids;

      patched = ownPatches != [ ] || anyChildPatched;

      src =
        if ownPatches == [ ] then
          input.outPath
        else
          applyPatches {
            name = "${name}-patched";
            patches = ownPatches;
            src = input.outPath;
          };

      result =
        if !patched then
          input
        else if !isFlake then
          throw (
            builtins.concatStringsSep "\n" [
              "fip: '${name}' must be re-imported but is not a Flake"
              ""
              "Something beneath it is patched, so its outputs have to be"
              "re-evaluated with the patched inputs -- but a non-Flake source"
              "(flake = false) has no flake.nix."
              ""
              "Patch a Flake input instead, or wrap this source in a Flake."
            ]
          )
        else
          let
            flake = import (src + "/flake.nix");
            outputs = flake.outputs (childValues // { self = result; });
          in
          outputs
          // {
            outPath = src;
            inputs = childValues;
            # The hash still describes the base source.
            sourceInfo = (input.sourceInfo or { }) // {
              outPath = src;
            };
            _type = "flake";
          };
    in
    {
      inherit patched result;
    };
in
# `self` is the consumer's own flake, not a dependency.
builtins.mapAttrs (_: v: v.result) (
  builtins.mapAttrs rebuild (builtins.removeAttrs unpatchedInputs [ "self" ])
)
