{
  inputs.dep1.follows = "dep1";

  outputs = inputs: {
    # dep1 is followed from the root flake and patched there, so these
    # reflect the patched values.
    value = inputs.dep1.value;
    set = inputs.dep1.set;
    systemFromDep1 = inputs.dep1.directAccessSystem;
    readme = inputs.dep1.subdirFlakeReadme;
  };
}
