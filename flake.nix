{
  description = "Declarative npm and bun global package management for Home Manager";

  inputs = { };

  outputs = { self, ... }: {
    homeManagerModules = {
      npm-globals = import ./module.nix;
      default = self.homeManagerModules.npm-globals;
    };

    # Alias used by some projects (e.g. catppuccin/nix)
    homeModules = self.homeManagerModules;
  };
}
