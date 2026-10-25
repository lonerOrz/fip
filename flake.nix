{
  description = "fip: patch flake inputs before Nix reads them";

  # No inputs by design: the library uses `builtins` alone, and the tools that
  # apply a patch are injected by the caller. There is no formatter output for
  # the same reason.
  outputs = _: {
    patchLib = import ./lib.nix;
  };
}
