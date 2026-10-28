{
  # nixpkgs' `lib` emits or-as-identifier warnings under `--accept-flake-config`.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Local fixtures (absolute paths for Lix compatibility).
    dep1 = {
      url = "path:/home/loner/Templates/fip/tests/dep1";
      inputs.systems.follows = "systems";
      inputs.subdirFlake.follows = "subdirFlake";
    };

    dep1-wrapper = {
      url = "path:/home/loner/Templates/fip/tests/dep1-wrapper";
      inputs.dep1.follows = "dep1";
    };

    systems = {
      url = "path:/home/loner/Templates/fip/tests/systems";
    };

    subdirFlake = {
      url = "path:/home/loner/Templates/fip/tests/subdirFlake";
    };
  };

  outputs =
    unpatchedInputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
      inherit (unpatchedInputs) dep1;

      # A path spec: fip imports it and calls the exported function.
      patchSpec = ./patch-spec.nix;

      # Patches build on this host, so every entry uses the host package set.
      hostPkgs = nixpkgs.legacyPackages.x86_64-linux;

      # `../.` is the live working tree, not a narHash-locked copy.
      patcherRoot = ../.;
      fixtures = ./.;

      # Fail loudly if the library under test is not this source tree.
      stalenessGuard = lib.optional (
        builtins.dirOf (builtins.toString fixtures) != builtins.toString patcherRoot
      ) "staleness-guard: library under test is not the live source tree";

      patchLib = import "${patcherRoot}/lib.nix";

      patched = patchLib.patchInputs { inherit unpatchedInputs patchSpec; };
      patchedWithPkgs = patchLib.patchInputs {
        inherit unpatchedInputs patchSpec;
        pkgs = hostPkgs;
      };
      byPlatform = patchLib.forSystemAttrs {
        inherit unpatchedInputs patchSpec;
        pkgs = hostPkgs;
        platforms = [
          "x86_64-linux"
          "aarch64-linux"
        ];
      };

      dep1Patched = patched.dep1;
      wrapperPatched = patched.dep1-wrapper;

      # An empty spec must be a true no-op at the consumer boundary.
      emptyPatched = patchLib.patchInputs {
        inherit unpatchedInputs;
        patchSpec = { };
      };
      unit =
        (import ./unit/spec-tests.nix { inherit lib patcherRoot; })
        ++ (import ./unit/patch-tree-tests.nix {
          inherit lib patcherRoot fixtures;
          runCommandLocal = nixpkgs.legacyPackages.x86_64-linux.runCommandLocal;
        })
        ++ (import ./unit/generate-wrapper-tests.nix {
          inherit lib patcherRoot fixtures;
          nixpkgs = nixpkgs.legacyPackages.x86_64-linux;
          runCommandLocal = nixpkgs.legacyPackages.x86_64-linux.runCommandLocal;
        })
        ++ (import ./unit/apply-patches-tests.nix {
          inherit lib patcherRoot fixtures;
          runCommandLocal = nixpkgs.legacyPackages.x86_64-linux.runCommandLocal;
        })
        ++ (import ./unit/flake-shape-tests.nix { inherit lib patcherRoot; });
      # Only the unpatched-passthrough half catches a node resolved to the wrong source.
      integration =
        lib.optional (dep1Patched.value != "you've been patched!") "dep1.value patched"
        ++ lib.optional (dep1Patched.set.new != "new") "dep1.set.new patched"
        ++ lib.optional (dep1Patched.directAccessSystem != "you've been patched!") "dep1.systems patched"
        ++ lib.optional (
          dep1Patched.indirectAccessSystem != "you've been patched!"
        ) "dep1.self.inputs.systems patched"
        ++ lib.optional (
          dep1Patched.subdirFlakeReadme != "patched this new file into existence!\n"
        ) "dep1.subdirFlake new file patched"
        ++ lib.optional (wrapperPatched.value != "you've been patched!") "dep1-wrapper.value patched"
        ++ lib.optional (wrapperPatched.set.new != "new") "dep1-wrapper.set.new patched"
        ++ lib.optional (
          wrapperPatched.systemFromDep1 != "you've been patched!"
        ) "dep1-wrapper.systems patched"
        ++ lib.optional (
          patched.dep1-wrapper.outPath != unpatchedInputs.dep1-wrapper.outPath
        ) "join: unpatched dep1-wrapper unchanged"
        ++ lib.optional (patched.dep1 == dep1) "core: patched dep1 is not the original"
        ++ lib.optional (patched.dep1.outPath == dep1.outPath) "core: patched dep1 has a new outPath"

        ++ lib.optional (
          patched.nixpkgs.outPath != unpatchedInputs.nixpkgs.outPath
        ) "join: unpatched nixpkgs unchanged"
        ++ lib.optional (
          patched.nixpkgs.legacyPackages.x86_64-linux.hello.name
          != unpatchedInputs.nixpkgs.legacyPackages.x86_64-linux.hello.name
        ) "join: unpatched nixpkgs is the real nixpkgs"

        ++ lib.optional (
          dep1Patched.inputs.systems.value or null != "you've been patched!"
        ) "join: patched node receives patched inputs"

        ++ lib.optional (
          builtins.length (builtins.attrNames byPlatform) != 2
        ) "forSystemAttrs: one entry per platform"
        ++ lib.optional (
          byPlatform.aarch64-linux.dep1.value != "you've been patched!"
        ) "forSystemAttrs: aarch64 set is applied"
        ++ lib.optional (
          byPlatform.x86_64-linux.dep1.value != "you've been patched!"
        ) "forSystemAttrs: x86_64 set is applied"

        ++ lib.optional (
          patchedWithPkgs.dep1.value != "you've been patched!"
        ) "patchInputs: explicit pkgs is honoured"

        # `self.inputs` must carry the patched tree; every other test would pass.
        ++ lib.optional (!(patched ? self)) "patchInputs: result has a self key"
        ++ lib.optional (
          patched.self.inputs.dep1.value != "you've been patched!"
        ) "patchInputs: self.inputs carries the patched dep1"
        ++ lib.optional (
          patched.self.inputs.dep1.outPath == unpatchedInputs.dep1.outPath
        ) "patchInputs: self.inputs.dep1 is a new store path"
        ++ lib.optional (
          patched.self.inputs.dep1-wrapper.value != "you've been patched!"
        ) "patchInputs: self.inputs carries a patched dependency's node"
        # Empty spec: the resolved value and the indirect access must match the
        # bare input.
        ++ lib.optional (
          emptyPatched.dep1.value != unpatchedInputs.dep1.value
        ) "empty-patchSpec: dep1.value matches bare input"
        ++ lib.optional (
          emptyPatched.dep1.indirectAccessSystem != unpatchedInputs.dep1.indirectAccessSystem
        ) "empty-patchSpec: dep1 indirect access matches bare input";

    in
    {

      failedTests = stalenessGuard ++ unit ++ integration;
    };
}
