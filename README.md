# harnix

Declarative npm and bun global package management for [Home Manager](https://github.com/nix-community/home-manager).

Declare your npm/bun globals in Nix. They get installed (and removed) automatically on `home-manager switch` or `nixos-rebuild switch`. No more `npm i -g` commands that drift out of sync.

## Features

- **Declarative** — list packages in your Nix config, done
- **Full sync** — packages removed from your config get uninstalled automatically
- **Version pinning** — `"pkg@1.2.3"`, `"@scope/pkg@latest"`
- **npm + bun** — manage both from one place
- **Non-destructive** — failures on individual packages don't block the rest
- **Cross-platform** — works on NixOS and macOS (nix-darwin)
- **Zero dependencies** — the flake has no inputs; your nixpkgs provides everything

## Quick Start

### 1. Add the flake input

```nix
# flake.nix
{
  inputs = {
    # ...your existing inputs...
    harnix.url = "github:max-miller1204/harnix";
  };
}
```

### 2. Import the module and declare packages

**Standalone Home Manager** (`home.nix` or similar):

```nix
{ inputs, ... }: {
  imports = [ inputs.harnix.homeManagerModules.default ];

  programs.harnix = {
    enable = true;
    npmPackages = [
      "@anthropic-ai/claude-code"
      "@openai/codex"
      "some-tool@2.1.0"
    ];
    bunPackages = [
      "some-bun-tool"
    ];
  };
}
```

**NixOS + Home Manager** (as a module):

```nix
# In your NixOS configuration where home-manager is set up
{ inputs, ... }: {
  home-manager.users.youruser = {
    imports = [ inputs.harnix.homeManagerModules.default ];

    programs.harnix = {
      enable = true;
      npmPackages = [
        "@anthropic-ai/claude-code"
      ];
    };
  };
}
```

### 3. Apply

```sh
# Home Manager standalone
home-manager switch

# NixOS
sudo nixos-rebuild switch

# nix-darwin
darwin-rebuild switch
```

That's it. Packages in your lists get installed; packages you remove get uninstalled.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the module |
| `npmPackages` | list of str | `[]` | npm packages to install globally |
| `bunPackages` | list of str | `[]` | bun packages to install globally |
| `enableBun` | bool | `true` | Whether to manage bun globals (and add bun to packages) |
| `npmPrefix` | str | `~/.npm-global` | Writable directory for npm global installs |
| `bunBinDir` | str | `~/.bun/bin` | Where bun places global binary symlinks |
| `bunGlobalDir` | str | `~/.bun/install/global` | Where bun installs global packages |
| `nodePackage` | package | `pkgs.nodejs` | Node.js package to use |
| `bunPackage` | package | `pkgs.bun` | Bun package to use |
| `manageNpmrc` | bool | `true` | Write `~/.npmrc` with the global prefix |

## How It Works

On each activation (switch), two scripts run:

1. **`syncNpmGlobals`** — compares `npm list -g --json` against your declared packages. Installs missing ones, removes undeclared ones.
2. **`syncBunGlobals`** — reads `~/.bun/install/global/node_modules` to find installed packages (bun has no `pm ls -g` command). Same install/remove logic.

Package lists are written as JSON manifests to `~/.config/harnix/` and diffed with `jq`. All tool paths are fully-qualified Nix store paths — no implicit `$PATH` dependencies.

## Version Pinning

```nix
npmPackages = [
  "pkg"              # latest
  "pkg@1.2.3"        # exact version
  "@scope/pkg"       # scoped, latest
  "@scope/pkg@^2.0"  # scoped with range
];
```

The version specifier is passed directly to `npm install -g` / `bun add -g`. Reconciliation uses only the package name (without version) to determine what's already installed.

## Disabling Bun

If you only need npm:

```nix
programs.harnix = {
  enable = true;
  enableBun = false;
  npmPackages = [ "some-tool" ];
};
```

This skips bun installation and the bun sync activation script entirely.

## Shell Support

**Fish**: Handled automatically. If `programs.fish.enable = true` in your Home Manager config, harnix adds `fish_add_path` lines to your fish shell init. No extra setup needed.

**Bash / Zsh**: PATH is added via `home.sessionPath`, which Home Manager writes into `hm-session-vars.sh`. This is sourced on login, so you may need to open a new terminal or re-login after your first `switch`.

> **Why the special fish handling?** Fish manages PATH separately from environment variables. `home.sessionPath` sets PATH in `hm-session-vars.sh`, which is sourced once at login — but fish can lose those additions. `fish_add_path` is idempotent and runs every interactive shell, so the PATH is always correct.

## Using with den

If you use the [den](https://github.com/vic/den) framework, create an aspect:

```nix
# modules/aspects/harnix.nix
{ inputs, ... }: {
  den.aspects.harnix = {
    homeManager = { ... }: {
      imports = [ inputs.harnix.homeManagerModules.default ];

      programs.harnix = {
        enable = true;
        npmPackages = [
          # your packages here
        ];
      };
    };
  };
}
```

Then include it in your user aspect:

```nix
# modules/aspects/your-user.nix
{ ... }: {
  den.aspects.your-user = {
    includes = [
      den.aspects.harnix
    ];
  };
}
```

## License

MIT
