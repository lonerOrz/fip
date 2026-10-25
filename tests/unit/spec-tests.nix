# Unit tests for `module/spec.nix`: tree + spec -> narHash -> [patches]
#
# Pure: no fetches, no IFD, no network. The tree below has the shape Nix hands
# `outputs`: `narHash`/`outPath` directly on each node, `outputs` present only
# on Flake inputs.
{ lib, patcherRoot }:

let
  resolveSpec = import "${patcherRoot}/module/spec.nix";

  # A 43-char base64-ish body, so `sha256-<body>` reads like a real SRI.
  hash = ch: "sha256-${lib.concatStringsSep "" (lib.replicate 43 ch)}=";
  a = hash "a";
  b = hash "b";
  c = hash "c";

  flake = narHash: outPath: inputs: {
    _type = "flake";
    inherit narHash inputs;
    outPath = "/nix/store/${outPath}-source";
    outputs = { };
  };

  # A non-Flake (`flake = false`) source: no `outputs`, no `inputs`.
  bare = narHash: outPath: {
    inherit narHash;
    outPath = "/nix/store/${outPath}-source";
  };

  # root -> dep (-> sub, bare), other
  # `alias` is the SAME attrset as `dep.sub`, standing in for a `follows`.
  tree = {
    self = {
      outPath = "/nix/store/self-source";
    };
    dep = flake a "dep" {
      sub = flake b "dep-sub" { };
      bare = bare c "dep-bare";
    };
    other = flake c "other" { };
  };

  treeWithAlias = tree // {
    alias = tree.dep.inputs.sub;
  };

  tryResolve = inputs: spec: builtins.tryEval (builtins.deepSeq (resolveSpec inputs spec) true);

  throws = inputs: spec: !(tryResolve inputs spec).success;

  got = resolveSpec tree {
    dep.patches = [ "p1.patch" ];
    dep.inputs.sub.patches = [ "p2.patch" ];
  };

  aliased = resolveSpec treeWithAlias {
    dep.inputs.sub.patches = [ "p2.patch" ];
    alias.patches = [ "p2.patch" ];
  };

  aliasedConflict = throws treeWithAlias {
    dep.inputs.sub.patches = [ "p2.patch" ];
    alias.patches = [ "p3.patch" ];
  };
in
[ ]
++ lib.optional (!(got ? ${a})) "spec: direct dependency keyed by narHash"
++ lib.optional (!(got ? ${b})) "spec: transitive dependency keyed by narHash"
++ lib.optional (got ? ${c}) "spec: an untouched sibling is absent"
++ lib.optional ((got.${a} or [ ]) != [ "p1.patch" ]) "spec: direct patches recorded"
++ lib.optional ((got.${b} or [ ]) != [ "p2.patch" ]) "spec: transitive patches recorded"

++ lib.optional (
  (aliased.${b} or [ ]) != [ "p2.patch" ]
) "spec: identical patches from two positions dedupe"
++ lib.optional (!aliasedConflict) "spec: conflicting patches from two positions must error"

++ lib.optional (
  !(throws tree { dep.inputs.nope.patches = [ "p.patch" ]; })
) "spec: patching a non-existent input must error"
++ lib.optional (
  !(throws tree { dep.inputs.bare.patches = [ "p.patch" ]; })
) "spec: patching a non-Flake input must error"
++ lib.optional (throws tree {
  dep.patches = [ ];
}) "spec: an empty patch list is a no-op, not an error"
