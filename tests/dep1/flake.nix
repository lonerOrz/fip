{
  outputs =
    {
      self,
      systems,
      subdirFlake,
    }:
    {
      value = import ./value.nix;
      set = import ./set.nix;
      directAccessSystem = systems.value;
      indirectAccessSystem = self.inputs.systems.value;
      subdirFlakeReadme = subdirFlake.readme;
    };
}
