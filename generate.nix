# Pre-eval: realises the patched sources outside the consumer's evaluation and
# emits a wrapper flake whose inputs are store paths, so the consumer needs no
# IFD. This module never imports a derivation; `buildPatched` is injected.
{
  unpatchedInputs,
  patchSpec,
  buildPatched ? null,
  runCommandLocal ? null,
  # Only a function spec uses this: it is passed to the function as `pkgs`.
  pkgs ? null,
}:

let
  resolveSpec = import ./module/spec.nix;
  flakeShape = import ./module/flake-shape.nix;

  # Injected by tests/CLI; defaults to realising through applyPatches.
  applyPatches = import ./module/apply-patches.nix { inherit runCommandLocal; };
  buildPatched' =
    if buildPatched != null then
      buildPatched
    else
      narHash: patches: src:
      (applyPatches {
        name = "${narHash}-patched";
        inherit patches src;
      }).outPath;

  patchesByNarHash = resolveSpec { inherit unpatchedInputs patchSpec pkgs; };

  roots = builtins.removeAttrs unpatchedInputs [ "self" ];

  # --- gather distinct sources (mirrors patch-tree.nix) -------------------
  # One source at several positions: key by narHash, keep the shallowest.
  gather =
    depth: input: acc:
    let
      narHash = input.narHash or null;
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

  ownPatchedByNar = builtins.mapAttrs (_: ps: ps != [ ]) patchesByNarHash;

  # Patched = own patches or any descendant. Children are sorted before parents,
  # so each child is already a thunk here -- no cycle.
  patchedByNar = builtins.listToAttrs (
    map (h: {
      name = h;
      value =
        let
          node = inputsByNar.${h};
          own = ownPatchedByNar.${h} or false;
          child = builtins.any (c: c.narHash or null != null && (patchedByNar.${c.narHash} or false)) (
            builtins.attrValues (node.inputs or { })
          );
        in
        own || child;
    }) sortedHashes
  );

  # Force the gate now so it throws even if nothing below is forced.
  gates = builtins.mapAttrs (
    h: _:
    let
      node = inputsByNar.${h};
    in
    if patchedByNar.${h} && !flakeShape node then
      throw (
        builtins.concatStringsSep "\n" [
          "fip: '${h}' must be re-imported but is not a Flake"
          ""
          "Something beneath it is patched, so its outputs have to be"
          "re-evaluated with the patched inputs -- but a non-Flake source"
          "(flake = false) has no flake.nix."
          ""
          "Patch a Flake input instead, or wrap this source in a Flake."
        ]
      )
    else
      true
  ) inputsByNar;
  _gatesForced = builtins.seq gates true;

  # Realise each own-patched source once, memoised by narHash.
  realizedByNar = builtins.listToAttrs (
    map (h: {
      name = h;
      value =
        if ownPatchedByNar.${h} or false then
          buildPatched' h (patchesByNarHash.${h}) (inputsByNar.${h}.outPath)
        else
          null;
    }) sortedHashes
  );

  # --- wrapper input specs (keyed by input name) --------------------------
  # Own-patched inputs point at their realised store path; the rest keep their
  # original `url`. Nested `follows` wiring is carried over, or Nix would look
  # up `flake:<name>` in the registries and the wrapper would not lock.
  rootNameByNarHash = builtins.listToAttrs (
    map (name: {
      name = roots.${name}.narHash or "";
      value = name;
    }) (builtins.attrNames roots)
  );

  childSpec =
    parent: childName: child:
    let
      narHash = child.narHash or null;
      rootName = if narHash != null then (rootNameByNarHash.${narHash} or null) else null;
    in
    if rootName != null then { follows = rootName; } else { url = "path:" + (child.outPath or ""); };

  nestedInputs =
    name: input:
    builtins.mapAttrs (childName: child: childSpec name childName child) (input.inputs or { });

  mkInputSpec =
    name: input:
    let
      narHash = input.narHash or null;
      ownPatched = narHash != null && (ownPatchedByNar.${narHash} or false);
      nested = nestedInputs name input;
      base =
        if ownPatched then
          { url = "path:" + realizedByNar.${narHash}; }
        else if input ? url && input.url != null then
          { url = input.url; }
        else if input ? outPath then
          { url = "path:" + input.outPath; }
        else
          { url = "path:" + (input.outPath or ""); };
    in
    base // (if nested == { } then { } else { inputs = nested; });
  rootSpecs = builtins.mapAttrs mkInputSpec roots;

  # Own-patched sources that only appear nested still need a root slot.
  rootHashes = builtins.listToAttrs (
    map (n: {
      name = roots.${n}.narHash or "";
      value = true;
    }) (builtins.attrNames roots)
  );
  sanitize = h: builtins.replaceStrings [ ":" "/" "+" "=" "-" ] [ "_" "_" "_" "_" "_" ] h;
  uncovered = builtins.filter (
    h: (ownPatchedByNar.${h} or false) && !(rootHashes ? ${h})
  ) sortedHashes;
  syntheticSpecs = builtins.listToAttrs (
    map (h: {
      name = "fip-" + sanitize h;
      value = {
        url = "path:" + realizedByNar.${h};
      };
    }) uncovered
  );

  wrapperSpecs = rootSpecs // syntheticSpecs;

  # --- audit trail (keyed by input name) ----------------------------------
  rootAudit = builtins.listToAttrs (
    builtins.concatLists (
      map (
        name:
        let
          input = roots.${name};
          narHash = input.narHash or null;
        in
        if narHash != null && (ownPatchedByNar.${narHash} or false) then
          [
            {
              name = name;
              value = {
                inherit narHash;
                baseNarHash = narHash;
                fipPatches = patchesByNarHash.${narHash};
                patchedOutPath = realizedByNar.${narHash};
              };
            }
          ]
        else
          [ ]
      ) (builtins.attrNames roots)
    )
  );
  syntheticAudit = builtins.listToAttrs (
    map (h: {
      name = "fip-" + sanitize h;
      value = {
        narHash = h;
        baseNarHash = h;
        fipPatches = patchesByNarHash.${h};
        patchedOutPath = realizedByNar.${h};
      };
    }) uncovered
  );

  audit = rootAudit // syntheticAudit;
  # The wrapper's `flake.nix` as a string: each input's `url` plus its nested
  # `inputs` wiring.
  serializeSpec =
    name: spec:
    let
      nested = spec.inputs or { };
      nestedText =
        if nested == { } then
          ""
        else
          let
            one =
              childName: child:
              "      ${childName} = { "
              + (if child ? follows then "follows = \"${child.follows}\"; " else "")
              + (if child ? url then "url = \"${child.url}\"; " else "")
              + "};";
          in
          " inputs = {\n"
          + builtins.concatStringsSep "\n" (
            map (childName: one childName nested.${childName}) (builtins.attrNames nested)
          )
          + "\n    };";
    in
    "    ${name} = { url = \"${spec.url}\";${nestedText} };";
  serializeInputs = builtins.concatStringsSep "\n" (
    map (name: serializeSpec name wrapperSpecs.${name}) (builtins.attrNames wrapperSpecs)
  );
  wrapperNix = ''
    {
      inputs = {
    ${serializeInputs}
      };
      # No IFD: every input is a store path or an unmodified original.
      outputs = inputs: inputs // { self = { inherit inputs; _type = "flake"; }; };
    }
  '';

  # The wrapper flake expression; `outputs` rebuilds `self` and re-exposes each
  # input at the top level.
  wrapper = {
    inputs = wrapperSpecs;
    outputs =
      inputs:
      let
        originalSelf = unpatchedInputs.self or { };
        self = originalSelf // {
          inputs = inputs;
          _type = "flake";
        };
      in
      inputs // { inherit self; };
  };
in
{
  # `{ inputs, outputs }`.
  inherit wrapper;
  # `flake.nix` source for the wrapper.
  inherit wrapperNix;
  # Top-level input specs, serialisable.
  wrapperInputs = wrapperSpecs;
  # Per-patched-input audit metadata.
  inherit audit;
}
