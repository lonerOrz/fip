# fip

Patch a specific **dependency (input)** of a flake.

## Usage

```nix
inputs.fip.url = "github:lonerOrz/fip";

outputs = unpatchedInputs@{ self, nixpkgs, fip, flake-parts, ... }:
let
  patchSpec = {
    hyprland.patches = [
      ./patches/local.patch
      (nixpkgs.fetchpatch {
        url = "https://github.com/hyprwm/Hyprland/pull/1234.diff";
        hash = "sha256-...";
      })
    ];
  };
  inputs = fip.patchLib.applyToInputs { inherit unpatchedInputs patchSpec; };
in
  flake-parts.lib.mkFlake { inherit inputs; } { /* No other changes needed */ };
```

The same approach works without `flake-parts`: simply add the `patchSpec` and `inputs` statements to `outputs`.

## API

| Call | Description |
|---|---|
| `applyToInputs { inherit unpatchedInputs patchSpec; }` | The most common use case. |
| `applyToInputs { inherit unpatchedInputs patchSpec; buildPlatform = "aarch64-darwin"; }` | Names the build platform when pure eval hides `builtins.currentSystem` and the host is not `x86_64-linux`. |
| `applyToInputs { inherit unpatchedInputs patchSpec; pkgs = <package set>; }` | Supplies the toolchain from somewhere other than your `nixpkgs` input. |
| `forSystemAttrs { inherit unpatchedInputs patchSpec; platforms = [ ... ]; }` | For hosts that support multiple build platforms. Returns `{ <platform> = <patched inputs>; }`. |

Applying a patch runs `patch` and coreutils in a derivation, so a package set is required. `pkgs` defaults to your own `nixpkgs` input at the build platform, and passing it makes `buildPlatform` irrelevant. `fip` itself has no `nixpkgs` input and uses only `builtins`.

## Module Structure

Arrows indicate the direction of `import`. Dependencies form a directed acyclic graph (DAG):

```text
lib.nix ─┬─► apply-to-self ──► patch-inputs ─┬─► spec
         │                                   ├─► patch-tree
         └───────────────────────────────────┴─► apply-patches
```

- `spec.nix` determines which patches to apply to which source trees. All validation and error reporting happen here.
- `patch-tree.nix` reconstructs the tree and only recognizes the mapping `narHash → [patches]`. The patch application logic is injected into it.
- `apply-patches.nix` applies a single patch.
- `patch-inputs.nix` wires these three modules together.
- `apply-to-self.nix` handles the entry-point arguments, including the build platform and function-based patch specifications.
- `lib.nix` exposes the public API.

## Contributing

```sh
nix flake check --accept-flake-config
nix run nixpkgs#nixfmt-tree                          # fip has no formatter output
nix eval ./tests#failedTests --accept-flake-config   # Expected output: []
```
