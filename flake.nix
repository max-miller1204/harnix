{
  description = "Declarative npm and bun global package management for Home Manager";

  inputs = { };

  outputs = { self, ... }: {
    homeManagerModules = {
      harnix = import ./module.nix;
      default = self.homeManagerModules.harnix;
    };

    # Alias used by some projects (e.g. catppuccin/nix)
    homeModules = self.homeManagerModules;
  };
}
