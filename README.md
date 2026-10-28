# fip

Patch one of your flake's inputs with your own changes.

## Usage

Copy this into your flake:

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
  inputs = fip.patchLib.patchInputs { inherit unpatchedInputs patchSpec; };
in
  flake-parts.lib.mkFlake { inherit inputs; } { /* nothing else changes */ };
```

- `patchSpec` says which input gets which patches. Keys are input names; nested ones work too (`dep1.inputs.sub`).
- `patchInputs` returns a new set of inputs in which the patched ones are already patched. Nothing else in your flake changes.
- Without flake-parts, put the `patchSpec` and `inputs` lines directly in `outputs`.

## Where patches come from

- A file in your repo: `./patches/fix.patch`
- A patch from the web: `(nixpkgs.fetchpatch { url = "..."; hash = "..."; })`
- A spec that gets long can live in its own file: `patchSpec = ./patch-spec.nix;`, holding what `patchSpec` held above.

## More control

- `patchTree` — the same patching, but returns only the patched inputs. Use it if you wire things yourself.
- `forSystemAttrs` — one patched set per platform, for a flake that serves several machines.

## Development

```sh
nix run nixpkgs#nixfmt-tree
nix eval ./tests#failedTests --accept-flake-config   # expected: []
```
