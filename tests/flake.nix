{
  # nixpkgs' `lib` emits or-as-identifier warnings under `--accept-flake-config`.
  nixConfig.extra-deprecated-features = [ "or-as-identifier" ];

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    fip = {
      url = "path:/home/loner/Templates/fip";
    };

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
      fip,
      ...
    }:
    let
      lib = nixpkgs.lib;
      inherit (unpatchedInputs) dep1;

      patchSpec = import ./patch-spec.nix;

      # The patch derivation runs on this machine, so every entry uses the
      # host package set. Naming a different build platform would ask for a
      # derivation this host cannot build.
      hostPkgs = nixpkgs.legacyPackages.x86_64-linux;

      patched = fip.patchLib.applyToInputs { inherit unpatchedInputs patchSpec; };
      patchedWithPkgs = fip.patchLib.applyToInputs {
        inherit unpatchedInputs patchSpec;
        pkgs = hostPkgs;
      };
      byPlatform = fip.patchLib.forSystemAttrs {
        inherit unpatchedInputs patchSpec;
        pkgs = hostPkgs;
        platforms = [
          "x86_64-linux"
          "aarch64-linux"
        ];
      };

      dep1Patched = patched.dep1;
      wrapperPatched = patched.dep1-wrapper;

      # A relative import from a store-copied test file resolves against the
      # store path's parent, so the modules are reached through this instead.
      patcherRoot = fip.outPath;
      fixtures = ./.;

      unit =
        (import ./unit/spec-tests.nix { inherit lib patcherRoot; })
        ++ (import ./unit/patch-tree-tests.nix {
          inherit lib patcherRoot fixtures;
          runCommandLocal = nixpkgs.legacyPackages.x86_64-linux.runCommandLocal;
        })
        ++ (import ./unit/generator-tests.nix {
          inherit lib patcherRoot fixtures;
          runCommandLocal = nixpkgs.legacyPackages.x86_64-linux.runCommandLocal;
        });

      # Only the unpatched-passthrough half catches a node resolved to the
      # wrong source.
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
          wrapperPatched.readme != "patched this new file into existence!\n"
        ) "dep1-wrapper.subdirFlake patched"

        ++ lib.optional (patched.dep1 == dep1) "core: patched dep1 is not the original"
        ++ lib.optional (patched.dep1.outPath == dep1.outPath) "core: patched dep1 has a new outPath"

        ++ lib.optional (
          patched.nixpkgs.outPath != unpatchedInputs.nixpkgs.outPath
        ) "join: unpatched nixpkgs unchanged"
        ++ lib.optional (patched.fip.outPath != unpatchedInputs.fip.outPath) "join: unpatched fip unchanged"
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
        ) "applyToInputs: explicit pkgs is honoured";
    in
    {
      inherit patched;

      failedTests = unit ++ integration;

      # Both entries build with the host toolchain, so `--all-systems` can
      # realise them here.
      packages = builtins.listToAttrs (
        map
          (
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
              dep1 = byPlatform.${system}.dep1;
            in
            {
              name = system;
              value = {
                hello-from-patched = pkgs.runCommandLocal "hello-from-patched" { } ''
                  echo "patched dep1 value: ${dep1.value}" > "$out"
                '';
              };
            }
          )
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
      );
    };
}
