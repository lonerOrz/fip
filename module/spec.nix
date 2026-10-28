# Resolves a `patchSpec` into `narHash -> [patches]`. Keyed by source, so one
# entry covers every position a `follows` target occupies.
let
  foldlAttrs =
    op: init: attrs:
    builtins.foldl' (acc: name: op acc name attrs.${name}) init (builtins.attrNames attrs);

  mapAttrsToList = f: attrs: builtins.map (name: f name attrs.${name}) (builtins.attrNames attrs);
  joinLines = builtins.concatStringsSep "\n";
  # Validation returns problems as data; throw the first.
  validatePatches = import ./validate-patch.nix;
  flakeShape = import ./flake-shape.nix;

  # Patches are a set, not a sequence: order is not a conflict.
  samePatches =
    xs: ys:
    (builtins.length xs == builtins.length ys) && (builtins.all (x: builtins.any (y: x == y) ys) xs);
in

{
  unpatchedInputs,
  patchSpec,
  # Only a function spec uses this: it is passed to the function as `pkgs`.
  pkgs ? null,
}:

let
  # A path literal is imported. A string is rejected: it is not carried into the
  # flake's store copy and would resolve against the cwd.
  spec =
    if builtins.isPath patchSpec then
      import patchSpec
    else if builtins.isString patchSpec then
      throw (joinLines [
        "fip: patchSpec is a string, not a path"
        ""
        "Got: \"${patchSpec}\""
        ""
        "Only a path literal (`./patch-spec.nix`) is imported. A string is not"
        "part of the flake's source tree, so it may be absent or stale when the"
        "flake is evaluated from its store copy."
        ""
        "Write the spec as a path literal, or pass the attrset/function itself."
      ])
    else
      patchSpec;

  # A function spec is called with the inputs plus `pkgs`; without a package set
  # there is nothing to call it with.
  specTree =
    if !(builtins.isFunction spec) then
      spec
    else if pkgs == null then
      throw (joinLines [
        "fip: this patch spec is a function"
        ""
        "A function spec is called with your inputs plus a `pkgs` alias, so it"
        "needs a package set. `patchInputs` resolves one from your `nixpkgs`"
        "input; `generateWrapper` and `patchTree` accept one explicitly:"
        ""
        "  generateWrapper { inherit unpatchedInputs patchSpec pkgs; }"
        ""
        "Or pass the resolved attrset instead of a function."
      ])
    else
      spec (unpatchedInputs // { pkgs = pkgs; });

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
            "to `patchInputs` was not the one Nix handed to `outputs`."
          ])
        else
          { ${narHash} = patches; };

      # Validate before realising anything, so a bad entry names its location.
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

  # Stand-in for the consumer's flake: `outputs` so it reads as a Flake, no
  # narHash so patching it is rejected.
  walked = walk [ ] {
    outputs = { };
    inputs = builtins.removeAttrs unpatchedInputs [ "self" ];
  } { inputs = specTree; };
in
walked.result
