# harnix

Declarative npm and bun global package management for [Home Manager](https://github.com/nix-community/home-manager).

Declare your npm/bun globals in Nix. They get installed (and removed) automatically on `home-manager switch` or `nixos-rebuild switch`. No more `npm i -g` commands that drift out of sync.

## Features

- **Declarative** — list packages in your Nix config, done
- **Full sync** — packages removed from your config get uninstalled automatically
- **Version pinning** — `"pkg@1.2.3"`, `"@scope/pkg@^2.0"` (`@latest` stays rolling)
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

That's it. Unpinned packages refresh on each activation, pinned packages update when you change the declared spec, and packages you remove get uninstalled.

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

1. **`syncNpmGlobals`** — compares `npm list -g --json` against your declared packages. Unpinned specs are refreshed every activation, pinned specs are refreshed when the declared spec changes, and undeclared packages are removed.
2. **`syncBunGlobals`** — reads `~/.bun/install/global/node_modules` to find installed packages (bun has no `pm ls -g` command). Same refresh/remove logic.

Package lists are written as JSON manifests to `~/.config/harnix/` and diffed with `jq`. Harnix also records the last applied pinned specs there so it can detect when a pinned package declaration changed. All tool paths are fully-qualified Nix store paths — no implicit `$PATH` dependencies.

## Version Pinning

```nix
npmPackages = [
  "pkg"              # refreshed to latest on each activation
  "pkg@latest"       # also refreshed on each activation
  "pkg@1.2.3"        # held until you change the spec
  "@scope/pkg"       # scoped, refreshed to latest on each activation
  "@scope/pkg@latest"# scoped latest tag, refreshed on each activation
  "@scope/pkg@^2.0"  # held until you change the spec
];
```

The version specifier is passed directly to `npm install -g` / `bun add -g`. Reconciliation uses the package name (without version) as the package identity, while tracking the last applied pinned spec to detect declared version changes. `@latest` is treated as a rolling tag, so it refreshes on every activation just like an unversioned package.

## When updates happen

Updates happen during activation:

```sh
home-manager switch
sudo nixos-rebuild switch
darwin-rebuild switch
```

`nix flake update` only refreshes flake inputs and does not run harnix's activation scripts, so it does not apply npm/bun package updates by itself.

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

## NixOS note for prebuilt binaries

Some npm or bun packages ship generic dynamically linked Linux binaries instead of pure JavaScript entrypoints. On NixOS, those binaries may fail to start unless you enable `nix-ld`.

Example NixOS configuration:

```nix
{
  programs.nix-ld.enable = true;
}
```

If a package fails with an error about dynamically linked executables or links to the NixOS `stub-ld` documentation, this is usually the fix.

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
