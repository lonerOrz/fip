# Rebuilds the tree, swapping in every patched source. `inputs` is the resolved
# graph already, so no lockfile is read. `applyPatches` is injected: this module
# knows a source changed, not how.
#
# Memoization: one source appears at several positions (a `follows` target or
# under several attribute names) but is the same attrset. Keyed by `narHash`,
# not position, each distinct source is computed once and substituted into every
# position, collapsing N positions to one re-import and derivation build.
applyPatches:

# narHash -> [patches], as produced by spec.nix.
patchesByNarHash:

unpatchedInputs:

let
  flakeShape = import ./flake-shape.nix;

  roots = builtins.removeAttrs unpatchedInputs [ "self" ];

  # Gather distinct sources depth-first, recording each one's depth. A child is
  # always deeper than its parent, so folding in ascending-depth order computes
  # every child before its parent. That ordering is what lets `compute` read a
  # child from `byHash` without forcing a cycle: the attrset is fully populated
  # with thunks before any value is forced.
  gather =
    depth: input: acc:
    let
      narHash = input.narHash or null;
      # Any representative works: the memo is keyed by source, not by position.
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
      # A narHash-less child is never own-patched (spec.nix rejects null-narHash
      # patching), so it can only be a re-imported ancestor. Recompute it per
      # position rather than memoize, because `patchesByNarHash` cannot key on it.
      childHasHash = c: c.narHash or null != null;
      anyChildPatched = builtins.any (c: childHasHash c && byHash.${c.narHash}.patched) (
        builtins.attrValues (input.inputs or { })
      );
      patched = ownPatches != [ ] || anyChildPatched;

      # Named by narHash, not position, so every position of this source shares
      # one derivation and Nix builds it once.
      ownPatched = ownPatches != [ ];
      # Null when this source has no own patches; it is then kept at its original
      # outPath and only re-imported because a descendant changed.
      patchedDerivation =
        if ownPatched then
          applyPatches {
            name = "${narHash}-patched";
            patches = ownPatches;
            src = input.outPath;
          }
        else
          null;
      # Forced to the patched store path, not the derivation thunk, so a
      # memoized node's `outPath` compares and stringifies as a path.
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
          let
            # Import-From-Derivation: when this node has its own patches,
            # `realSrc` is the outPath of a derivation built by apply-patches, so
            # importing its flake.nix is genuine IFD. This is required, not
            # incidental: a flake.nix that reads files the patch modifies must be
            # evaluated from the patched directory. Do not run Nix with
            # `--option allow-import-from-derivation false` on a flake that uses
            # fip.
            realSrc = if ownPatched then srcPath else input.outPath;
            flake = import (realSrc + "/flake.nix");
            # `self` is this node itself, so a flake's outputs can reference it
            # through `self.inputs.<child>`.
            self = outputs // {
              outPath = srcPath;
              inputs = childValues;
              # The hash still describes the base source; only outPath changes.
              sourceInfo = (input.sourceInfo or { }) // {
                outPath = srcPath;
              };
              _type = "flake";
            };
            outputs = flake.outputs (childValues // { inherit self; });
          in
          self;
    in
    {
      inherit patched result;
    };

  # One entry per distinct source, in dependency order (children first), so
  # `compute` reads each child from `byHash` before forcing its own result.
  byHash = builtins.listToAttrs (
    builtins.map (narHash: {
      name = narHash;
      value = compute narHash inputsByNar.${narHash};
    }) sortedHashes
  );

  # Walk the original tree and swap each memoized source for its computed result.
  # A memoized result already carries its substituted children, so those
  # positions are not re-walked.
  substitute =
    _: input:
    let
      narHash = input.narHash or null;
    in
    if narHash != null && byHash ? ${narHash} then
      byHash.${narHash}.result
    else
      # No narHash: keep this node, but substitute its children so a patched
      # descendant is still swapped in.
      input
      // {
        inputs = builtins.mapAttrs substitute (input.inputs or { });
      };

  hasPatches = builtins.foldl' (acc: v: acc || v != [ ]) false (builtins.attrValues patchesByNarHash);
in
# Rebuild when any patches exist; short-circuit to the original tree otherwise.
if !hasPatches then roots else builtins.mapAttrs substitute roots
