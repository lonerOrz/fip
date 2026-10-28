# `resolveSpec` must surface bad patches as errors, but Nix's `tryEval` cannot
# recover a thrown message, so a unit test cannot assert on it. This module
# returns the problems as data (a list of human-readable strings) so a test can
# inspect them while the caller throws the first. An empty list means every
# patch is usable.
#
# A usable patch is either a derivation (what `pkgs.fetchpatch` returns) or a
# path to an existing file on disk. Anything else, or a missing path, is a
# problem, and each problem names the offending patch and the spec location.
where: patches:
let
  # Nix lacks this; `attrNames` is sorted, so order matches nixpkgs'.
  isDerivation = x: builtins.isAttrs x && (x.type or null) == "derivation";

  joinLines = builtins.concatStringsSep "\n";
in
builtins.foldl' (
  acc: p:
  let
    problem =
      if isDerivation p then
        null
      else if builtins.isPath p then
        if builtins.pathExists p then
          null
        else
          joinLines [
            "fip: a patch file is missing from disk"
            ""
            "At: ${where}"
            "Missing: ${toString p}"
            ""
            "Patch paths are resolved relative to the file that lists them."
            "Check the path is spelled correctly and the file exists there."
          ]
      else
        joinLines [
          "fip: a patch is neither a local file nor a fetched derivation"
          ""
          "At: ${where}"
          "Got: ${builtins.typeOf p}"
          ""
          "A patch must be either a path to a local .patch file (e.g. ./fix.patch)"
          "or a derivation from pkgs.fetchpatch. Remove or correct this entry."
        ];
  in
  if problem == null then acc else acc ++ [ problem ]
) [ ] patches
