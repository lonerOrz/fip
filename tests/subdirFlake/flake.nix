{
  outputs = { self }: {
    readme = builtins.readFile ./new-file-from-patch.md;
  };
}
