{
  inputs.dep1.follows = "dep1";

  outputs = inputs: {
    # Patched at the root through `follows`, so these are the patched values.
    value = inputs.dep1.value;
    set = inputs.dep1.set;
    systemFromDep1 = inputs.dep1.directAccessSystem;
    readme = inputs.dep1.subdirFlakeReadme;
  };
}
