# Problems as data, so tests can assert on them; `resolveSpec` throws the first.
# A usable patch is a derivation or a path to an existing file.
where: patches:
let
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
