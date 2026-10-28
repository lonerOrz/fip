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
| `patchLib.patch { inherit unpatchedInputs patchSpec; runCommandLocal = ...; }` | The engine: a pure tree transform. Takes `unpatchedInputs`, `patchSpec`, and an injected `runCommandLocal` (the toolchain provider), and returns the patched input tree only, with no `self` key. Assembling `self` is the entry point's job. |

Applying a patch runs `patch` and coreutils in a derivation, so a package set is required. `pkgs` defaults to your own `nixpkgs` input at the build platform, and passing it makes `buildPlatform` irrelevant. `fip` itself has no `nixpkgs` input and uses only `builtins`.

## Module structure

Dependency graph (arrows are `import`):

```text
lib.nix ──► apply-to-self ──► patch-inputs ─┬─► spec ──────► validate-patch
                                           ├─► patch-tree ─┤
                                           └─► apply-patches

flake-shape ◄──────────────── spec, patch-tree
```

- `spec.nix` decides which patches apply to which sources and throws on invalid input; the actual validation lives in `validate-patch.nix`.
- `patch-tree.nix` reconstructs the tree, keyed by `narHash -> [patches]`, re-importing and rebuilding each distinct source once.
- `apply-patches.nix` applies a single patch.
- `patch-inputs.nix` wires the modules together.
- `apply-to-self.nix` handles the entry-point arguments (build platform, function-based specs).
- `validate-patch.nix` validates each patch as data and returns problems for spec.nix to throw.
- `flake-shape.nix` holds the single `isFlake` predicate shared by `spec.nix` and `patch-tree.nix`.
- `lib.nix` exposes the public API.

## Import-From-Derivation is required

When a patched input has patches of its own (`patchesByNarHash` has an entry
for that source's `narHash`), `patch-tree.nix` builds a derivation from
`apply-patches.nix` and then `import`s that derivation's `flake.nix`:

```nix
srcPath = if ownPatched then patchedDerivation.outPath else input.outPath;
realSrc = if ownPatched then srcPath else input.outPath;
flake = import (realSrc + "/flake.nix");
```

`srcPath` forces the patched derivation's `.outPath` into a store-path string
before it is used, so `realSrc` is the path, not a derivation thunk.

This is genuine **Import-From-Derivation (IFD)** and it is unavoidable: a
`flake.nix` that reads files the patch modifies (a generated README, a patched
`default.nix`) must be evaluated from the patched directory, not the original
source. fip therefore needs `allow-import-from-derivation`, which is **enabled
by default**. Do NOT run Nix with
`--option allow-import-from-derivation false` (or `allow-import-from-derivation
= false` in `nix.conf`) on a flake that uses fip -- it hard-errors at the
re-import site:

```text
error: cannot build '...-patched.drv^out' during evaluation because the option
'allow-import-from-derivation' is disabled
```

An input that is patched only through a descendant (no own patches) is kept at
its original source and merely re-evaluated against the patched child, so it
does not itself trigger IFD.

## Contributing

The test suite evaluates the LIVE working tree: the library is imported from
the repo root via `patcherRoot = ../.`, and the tests flake deliberately has
no `fip` input, so you are testing the source you are editing -- not a
narHash-locked copy. Run it with:

```sh
nix flake check --accept-flake-config
nix run nixpkgs#nixfmt-tree                          # fip has no formatter output
nix eval ./tests#failedTests --accept-flake-config   # Expected output: []
```
