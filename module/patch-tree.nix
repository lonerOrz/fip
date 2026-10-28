# Rebuilds the tree, swapping in every patched source. `applyPatches` is injected.
# Sources are memoised by narHash, so a `follows` target at N positions is built
# and re-imported once.
applyPatches:

# narHash -> [patches], as produced by spec.nix.
patchesByNarHash:

unpatchedInputs:

let
  flakeShape = import ./flake-shape.nix;

  roots = builtins.removeAttrs unpatchedInputs [ "self" ];

  # Gather distinct sources with their depth. Children are always deeper, so
  # ascending-depth order computes each child before its parent: no cycle.
  gather =
    depth: input: acc:
    let
      narHash = input.narHash or null;
      # Any representative works; keep the shallowest.
      acc' =
        if narHash == null then
          acc
        else if acc.order ? ${narHash} && acc.order.${narHash} <= depth then
          acc
        else
          acc
          // {
            order = acc.order // {
              ${narHash} = depth;
            };
            inputs = acc.inputs // {
              ${narHash} = input;
            };
          };
    in
    builtins.foldl' (a: c: gather (depth + 1) c a) acc' (builtins.attrValues (input.inputs or { }));

  gathered = builtins.foldl' (a: root: gather 0 root a) {
    order = { };
    inputs = { };
  } (builtins.attrValues roots);

  inputsByNar = gathered.inputs;
  sortedHashes = builtins.sort (a: b: gathered.order.${a} < gathered.order.${b}) (
    builtins.attrNames inputsByNar
  );

  compute =
    narHash: input:
    let
      ownPatches = if narHash == null then [ ] else patchesByNarHash.${narHash} or [ ];

      childValues = builtins.mapAttrs (
        _: child: if child.narHash or null != null then byHash.${child.narHash}.result else child
      ) (input.inputs or { });
      # No narHash: never own-patched, so recompute per position.
      childHasHash = c: c.narHash or null != null;
      anyChildPatched = builtins.any (c: childHasHash c && byHash.${c.narHash}.patched) (
        builtins.attrValues (input.inputs or { })
      );
      patched = ownPatches != [ ] || anyChildPatched;

      # Named by narHash so every position shares one derivation.
      ownPatched = ownPatches != [ ];
      patchedDerivation =
        if ownPatched then
          applyPatches {
            name = "${narHash}-patched";
            patches = ownPatches;
            src = input.outPath;
          }
        else
          null;
      # The store path, not the derivation: `outPath` must compare as a path.
      srcPath = if ownPatched then patchedDerivation.outPath else input.outPath;
      result =
        if !patched then
          input
        else if !flakeShape input then
          throw (
            builtins.concatStringsSep "\n" [
              "fip: '${narHash}' must be re-imported but is not a Flake"
              ""
              "Something beneath it is patched, so its outputs have to be"
              "re-evaluated with the patched inputs -- but a non-Flake source"
              "(flake = false) has no flake.nix."
              ""
              "Patch a Flake input instead, or wrap this source in a Flake."
            ]
          )
        else
          # Genuine IFD when patched: the flake.nix must be read from the
          # patched directory.
          let
            realSrc = if ownPatched then srcPath else input.outPath;
            flake = import (realSrc + "/flake.nix");
            # Rebuild from `input` so original attributes survive; `sourceInfo`
            # is only added where it changes.
            sourceInfo' =
              let
                base = input.sourceInfo or { };
              in
              if ownPatched then
                base
                // {
                  outPath = srcPath;
                  baseNarHash = input.narHash or null;
                  fipPatches = ownPatches;
                }
              else
                base;
            # Only surface `sourceInfo` when it carries something.
            selfExtra = if sourceInfo' == { } then { } else { sourceInfo = sourceInfo'; };
            flakeOutputs = flake.outputs (childValues // { inherit self; });
            self =
              input
              // flakeOutputs
              // {
                outPath = srcPath;
                inputs = childValues;
                _type = "flake";
              }
              // selfExtra;
          in
          self;
    in
    {
      inherit patched result;
    };

  # One entry per source, children first, so `compute` never forces a cycle.
  byHash = builtins.listToAttrs (
    builtins.map (narHash: {
      name = narHash;
      value = compute narHash inputsByNar.${narHash};
    }) sortedHashes
  );

  # Swap each memoised source for its result; re-walk only nodes without a
  # narHash.
  substitute =
    _: input:
    let
      narHash = input.narHash or null;
    in
    if narHash != null && byHash ? ${narHash} then
      byHash.${narHash}.result
    else
      input
      // {
        inputs = builtins.mapAttrs substitute (input.inputs or { });
      };

  hasPatches = builtins.foldl' (acc: v: acc || v != [ ]) false (builtins.attrValues patchesByNarHash);
in
if !hasPatches then roots else builtins.mapAttrs substitute roots
