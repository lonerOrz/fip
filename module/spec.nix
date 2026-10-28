# Resolves a `patchSpec` into `narHash -> [patches]`, keyed by source rather than
# tree position: a node reached through `follows` is the same attrset, so one
# entry covers every position it occupies.
let
  # `attrNames` is sorted, so iteration order matches nixpkgs' (deterministic).
  foldlAttrs =
    op: init: attrs:
    builtins.foldl' (acc: name: op acc name attrs.${name}) init (builtins.attrNames attrs);

  mapAttrsToList = f: attrs: builtins.map (name: f name attrs.${name}) (builtins.attrNames attrs);
  joinLines = builtins.concatStringsSep "\n";
  # Validation lives in validate-patch.nix and returns problems as data so a test
  # can inspect them; we throw the first.
  validatePatches = import ./validate-patch.nix;
  flakeShape = import ./flake-shape.nix;

  # Patches for a source are a set, not a sequence: the same patches in a
  # different order are not a conflict.
  samePatches =
    xs: ys:
    (builtins.length xs == builtins.length ys) && (builtins.all (x: builtins.any (y: x == y) ys) xs);
in

unpatchedInputs: patchSpec:

let
  merge =
    acc: m:
    foldlAttrs (
      a: narHash: patches:
      if a ? ${narHash} && !(samePatches a.${narHash} patches) then
        throw (joinLines [
          "fip: the same input is patched from two places in the spec"
          ""
          "Source: ${narHash}"
          ""
          "Patches are keyed by source, so listing one under two spec paths"
          "registers it twice. The two entries disagree on which patches to"
          "apply, so the result is ambiguous. Keep a single entry -- it already"
          "applies everywhere that source appears, including through `follows`."
        ])
      else if a ? ${narHash} then
        a
      else
        a // { ${narHash} = patches; }
    ) acc m;

  walk =
    path: input: spec:
    let
      narHash = input.narHash or null;
      patches = spec.patches or [ ];
      childSpecs = spec.inputs or { };
      childInputs = input.inputs or { };

      where = builtins.concatStringsSep "." path;

      own =
        if patches == [ ] then
          { }
        else if path == [ ] then
          throw (joinLines [
            "fip: the spec patches the root flake"
            ""
            "A patch spec describes DEPENDENCIES. To change your own flake,"
            "edit its files -- there is nothing to patch before Nix reads them."
          ])
        else if !flakeShape input then
          throw (joinLines [
            "fip: cannot patch a non-Flake input"
            ""
            "Input: ${where}"
            "Reason: this input is a non-Flake source (flake = false). It has"
            "no flake.nix, so its outputs cannot be re-evaluated after patching."
            ""
            "Remove this patch specification, or wrap the source in a Flake."
          ])
        else if narHash == null then
          throw (joinLines [
            "fip: '${where}' has no narHash"
            ""
            "Patches are keyed by the input's source hash, and this input did"
            "not provide one. This usually means the `inputs` argument passed"
            "to `applyToInputs` was not the one Nix handed to `outputs`."
          ])
        else
          { ${narHash} = patches; };

      # Validate every patch here, before any subtree is realised, so a bad entry
      # surfaces immediately with its exact location rather than as a generic Nix
      # failure at build time. The validator returns its findings as data; we
      # throw the first.
      localFilesPresent =
        let
          problems = validatePatches where patches;
        in
        if problems == [ ] then true else throw (builtins.elemAt problems 0);

      children = mapAttrsToList (
        name: childSpec:
        let
          child =
            childInputs.${name} or (throw (joinLines [
              "fip: '${builtins.concatStringsSep "." (path ++ [ name ])}' is not an input"
              ""
              "The spec patches a child named '${name}' here, but this input"
              "declares no such input. Check the spelling, and check whether"
              "the dependency declares it at all."
            ]));
        in
        (walk (path ++ [ name ]) child childSpec).result
      ) childSpecs;
    in
    {
      # `seq` forces the check even when no patch in this subtree is realised.
      result = builtins.seq localFilesPresent (builtins.foldl' merge own children);
    };

  # Stand-in for the consumer's flake. It has `outputs` so it is not mistaken
  # for a non-Flake source, and no narHash so patching it is rejected above.
  walked = walk [ ] {
    outputs = { };
    inputs = builtins.removeAttrs unpatchedInputs [ "self" ];
  } { inputs = patchSpec; };
in
walked.result
