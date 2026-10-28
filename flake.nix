{
  description = "fip: patch flake inputs before Nix reads them";

  # No inputs: the library uses only `builtins`, and the patch tools are injected
  # by the caller. There is no formatter output for the same reason.
  outputs = _: {
    patchLib = import ./lib.nix;
  };
}
