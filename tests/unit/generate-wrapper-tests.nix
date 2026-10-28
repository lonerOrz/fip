# Pre-eval tests: wrapper generation, audit metadata, and the no-IFD proof. Pure:
# `buildPatched` is a mock; the proof locks and evaluates a real wrapper.
{
  lib,
  patcherRoot,
  fixtures,
  nixpkgs,
  runCommandLocal,
}:

let
  generate = import "${patcherRoot}/generate.nix";

  applyPatches = import "${patcherRoot}/module/apply-patches.nix" { inherit runCommandLocal; };
  resolveSpec = import "${patcherRoot}/module/spec.nix";

  hash = ch: "sha256-${lib.concatStringsSep "" (lib.replicate 43 ch)}=";
  sysHash = hash "s";
  subHash = hash "u";
  depHash = hash "d";
  nixpkgsHash = hash "n";

  # Paths (not strings), defined once so audit assertions compare the same values.
  dep1PatchA = ../dep1-int-to-str.patch;
  dep1PatchB = ../dep1-change-attrset.patch;
  subdirPatch = ../new-file.patch;
  systemsPatchPath = ../systems.patch;

  # Mirrors what Nix hands `outputs` for the fixture flakes.
  flake = narHash: outPath: inputs: {
    _type = "flake";
    inherit narHash inputs;
    outPath = outPath;
    outputs = { };
  };

  systemsNode = flake sysHash "${fixtures}/systems" { };
  subdirNode = flake subHash "${fixtures}/subdirFlake" { };
  nixpkgsNode = flake nixpkgsHash "${nixpkgs.path}" { };

  tree = {
    self = {
      outPath = "${fixtures}/self";
    };
    nixpkgs = nixpkgsNode;
    systems = systemsNode;
    subdirFlake = subdirNode;
    dep1 = flake depHash "${fixtures}/dep1" {
      # `follows systems`: literally the same value.
      systems = systemsNode;
      subdirFlake = subdirNode;
    };
  };

  patchSpec = {
    dep1.patches = [
      dep1PatchA
      dep1PatchB
    ];
    systems.patches = [ systemsPatchPath ];
    subdirFlake.patches = [ subdirPatch ];
  };

  # Mock `buildPatched`: realises through applyPatches, once per narHash.
  buildPatched =
    narHash: patches: src:
    (applyPatches {
      name = "${narHash}-patched";
      inherit patches src;
    }).outPath;

  # Drive every audit assertion from one real resolveSpec call.
  expected = resolveSpec {
    unpatchedInputs = tree;
    inherit patchSpec;
  };

  result = generate {
    unpatchedInputs = tree;
    inherit patchSpec buildPatched;
  };

  # A spec path must yield the same wrapper and audit as the inline attrset.
  systemsOnlySpec = {
    systems.patches = [ systemsPatchPath ];
  };
  resultSystemsOnly = generate {
    unpatchedInputs = tree;
    patchSpec = systemsOnlySpec;
    inherit buildPatched;
  };
  resultFromPath = generate {
    unpatchedInputs = tree;
    patchSpec = ./fixtures/spec-systems.nix;
    inherit buildPatched;
  };
  # A function spec resolves when `pkgs` is supplied.
  resultFromFunctionFile = generate {
    unpatchedInputs = tree;
    patchSpec = ./fixtures/spec-systems-fn.nix;
    pkgs = { };
    inherit buildPatched;
  };

  # --- the definitive no-IFD proof ----------------------------------------
  patchedSystemsPath =
    (applyPatches {
      name = "proof-systems-patched";
      patches = [ systemsPatchPath ];
      src = systemsNode.outPath;
    }).outPath;

  # Uses generate.nix's real `wrapperNix`, not a hand-written literal.
  wrapperPath =
    runCommandLocal "mode-b-proof-wrapper"
      {
        # An env var, not interpolation: a string may not refer to a store path.
        wrapperNix = result.wrapperNix;
        # `nix` must be on PATH; redirect its state to the sandbox.
        nativeBuildInputs = [ nixpkgs.nix ];
        HOME = "/build/home";
        NIX_STATE_DIR = "/build/state";
        NIX_CONFIG = "experimental-features = nix-command flakes";
      }
      ''
        mkdir -p "$HOME" "$NIX_STATE_DIR"
        mkdir -p "$out"
        printf '%s\n' "$wrapperNix" > "$out/flake.nix"
        echo "wrote flake.nix:" >&2
        cat "$out/flake.nix" >&2
        cd "$out"
        nix flake lock --accept-flake-config
        echo "lock wrote:" >&2
        cat flake.lock >&2
      '';

  proofEval =
    runCommandLocal "mode-b-proof-eval"
      {
        inherit wrapperPath;
        nativeBuildInputs = [ nixpkgs.nix ];
      }
      ''
        export HOME="$PWD/home"; mkdir -p "$HOME"
        export NIX_STATE_DIR="$PWD/state"; mkdir -p "$NIX_STATE_DIR"
        export NIX_CONFIG="experimental-features = nix-command flakes"
        cd "$wrapperPath"
        if nix eval --raw --option allow-import-from-derivation false .#systems.value > "$out" 2>"$HOME/err"; then
          echo "IFD-disabled eval succeeded" >&2
        else
          echo "IFD-disabled eval FAILED:" >&2
          cat "$HOME/err" >&2
          echo "IFD-ERROR" > "$out"
        fi
      '';
  proofValue = builtins.readFile proofEval;

  # The serialisable audit must match resolveSpec too.
  auditJson = builtins.toJSON result.audit;

  auditHasDep1 = result.audit ? dep1;
  auditHasSystems = result.audit ? systems;
in
[ ]
++ lib.optional (!(result ? wrapper)) "modeb: produces a wrapper attrset"
++ lib.optional (
  !(result.wrapperInputs ? dep1) || !(result.wrapperInputs ? systems)
) "modeb: wrapper inputs carry every root input"
++ lib.optional (
  !(result.wrapperInputs ? systems)
  || result.wrapperInputs.systems.url or "" != "path:" + (result.audit.systems.patchedOutPath or "")
) "modeb: wrapper points the patched input at the realised path"
++ lib.optional (!auditHasDep1) "modeb: audit carries dep1"
++ lib.optional (!auditHasSystems) "modeb: audit carries systems"
# A spec path is imported by generate, not walked as a value with no `patches`.
++ lib.optional (
  resultFromPath.wrapperInputs != resultSystemsOnly.wrapperInputs
) "modeb: a spec path yields the same wrapper inputs as the inline attrset"
++ lib.optional (
  resultFromPath.audit != resultSystemsOnly.audit
) "modeb: a spec path yields the same audit as the inline attrset"
++ lib.optional (
  resultFromFunctionFile.wrapperInputs != resultSystemsOnly.wrapperInputs
) "modeb: a function spec resolves when generate is given pkgs"
++ lib.optional (
  resultFromFunctionFile.audit != resultSystemsOnly.audit
) "modeb: a function spec yields the same audit as the inline attrset"
# The audit JSON must be derivable from resolveSpec's narHash -> [patches].
++ lib.optional (
  !(lib.hasInfix (lib.strings.escapeNixString sysHash) auditJson)
) "modeb: audit JSON contains the patched source hash"
# Each patched source is realised once and audited once.
++ lib.optional (
  builtins.length (builtins.attrNames result.audit) != 3
) "modeb: audit lists exactly the 3 patched sources"
# Nested `follows` must survive, or Nix looks up `flake:systems`.
++ lib.optional (
  ((result.wrapperInputs.dep1.inputs or { }).systems.follows or "") != "systems"
) "modeb: wrapper keeps dep1's nested follows wiring for systems"
++ lib.optional (
  ((result.wrapperInputs.dep1.inputs or { }).subdirFlake.follows or "") != "subdirFlake"
) "modeb: wrapper keeps dep1's nested follows wiring for subdirFlake"
++ lib.optional (
  !lib.hasInfix "follows = \"systems\"" result.wrapperNix
) "modeb: serialised wrapper carries the nested follows wiring"
# The wrapper evaluates with IFD disabled and returns the patched value.
++ lib.optional (proofValue == "IFD-ERROR") "modeb: no-IFD proof eval errored"
++ lib.optional (
  lib.trim proofValue != "you've been patched!"
) "modeb: no-IFD proof returns the patched value with IFD disabled"
# The audit must agree with a real resolveSpec call, not hand-copied constants.
++ lib.optional (
  auditHasDep1 && result.audit.dep1.fipPatches != expected.${result.audit.dep1.narHash}
) "modeb: audit.dep1.fipPatches agrees with resolveSpec"
++ lib.optional (
  auditHasSystems && result.audit.systems.fipPatches != expected.${result.audit.systems.narHash}
) "modeb: audit.systems.fipPatches agrees with resolveSpec"
++ lib.optional (
  auditHasDep1 && result.audit.dep1.baseNarHash != result.audit.dep1.narHash
) "modeb: audit.dep1.baseNarHash is the source hash"
++ lib.optional (
  auditHasSystems && result.audit.systems.baseNarHash != result.audit.systems.narHash
) "modeb: audit.systems.baseNarHash is the source hash"
