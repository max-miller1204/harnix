{ config, pkgs, lib, ... }:

let
  cfg = config.programs.harnix;

  # Strip version specifier: "@scope/pkg@1.0" → "@scope/pkg", "pkg@1.0" → "pkg"
  stripVersion = spec:
    let
      parts = lib.splitString "@" spec;
    in
      if lib.hasPrefix "@" spec
      then "@" + builtins.elemAt parts 1
      else builtins.head parts;

  npmGlobalNames = map stripVersion cfg.npmPackages;
  bunGlobalNames = map stripVersion cfg.bunPackages;

  npm = "${cfg.nodePackage}/bin/npm";
  jq  = "${pkgs.jq}/bin/jq";
  bun = "${cfg.bunPackage}/bin/bun";
  ls  = "${pkgs.coreutils}/bin/ls";

in {

  options.programs.harnix = {
    enable = lib.mkEnableOption "declarative npm and bun global package management";

    npmPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "@anthropic-ai/claude-code" "@mariozechner/pi-coding-agent" "gsd-pi@1.2.3" ];
      description = ''
        List of npm packages to install globally. Supports version pinning
        with `@` suffix (e.g. `"pkg@1.2.3"`). Scoped packages work too
        (e.g. `"@scope/pkg"`).

        Packages removed from this list will be uninstalled on next activation.
      '';
    };

    bunPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "some-bun-tool" ];
      description = ''
        List of bun packages to install globally. Same version pinning
        syntax as npmPackages.

        Packages removed from this list will be uninstalled on next activation.
      '';
    };

    npmPrefix = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.npm-global";
      description = ''
        Directory for npm global installations. Must be writable (the Nix
        store is not). Defaults to `~/.npm-global`.
      '';
    };

    bunBinDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.bun/bin";
      description = "Directory where bun places global binary symlinks.";
    };

    bunGlobalDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.bun/install/global";
      description = "Directory where bun installs global packages.";
    };

    enableBun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install bun and manage bun global packages.
        Set to false if you only need npm globals.
      '';
    };

    nodePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs;
      defaultText = lib.literalExpression "pkgs.nodejs";
      description = "The Node.js package to use for npm.";
    };

    bunPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bun;
      defaultText = lib.literalExpression "pkgs.bun";
      description = "The bun package to use.";
    };

    manageNpmrc = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to manage `~/.npmrc` with the global prefix setting.
        Disable if you manage `.npmrc` yourself.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Packages ────────────────────────────────────────────
    home.packages = lib.optional cfg.enableBun cfg.bunPackage;

    # ── npm prefix config (writable global dir) ─────────────
    home.file.".npmrc" = lib.mkIf cfg.manageNpmrc {
      text = "prefix=${cfg.npmPrefix}\n";
    };

    # ── PATH for global bins ────────────────────────────────
    home.sessionPath =
      [ "${cfg.npmPrefix}/bin" ]
      ++ lib.optional cfg.enableBun cfg.bunBinDir;

    # fish_add_path is idempotent and persists — needed because fish
    # doesn't reliably pick up home.sessionPath from hm-session-vars.
    programs.fish.interactiveShellInit = lib.mkIf config.programs.fish.enable
      (let
        paths = [ "${cfg.npmPrefix}/bin" ]
          ++ lib.optional cfg.enableBun cfg.bunBinDir;
      in lib.concatMapStringsSep "\n"
        (p: "fish_add_path --prepend ${p}") paths);

    # ── Declared package manifests (read by activation) ─────
    home.file.".config/harnix/npm-names.json".text =
      builtins.toJSON npmGlobalNames;
    home.file.".config/harnix/npm-specs.json".text =
      builtins.toJSON cfg.npmPackages;
    home.file.".config/harnix/bun-names.json" = lib.mkIf cfg.enableBun {
      text = builtins.toJSON bunGlobalNames;
    };
    home.file.".config/harnix/bun-specs.json" = lib.mkIf cfg.enableBun {
      text = builtins.toJSON cfg.bunPackages;
    };

    # ── Activation: sync npm globals ────────────────────────
    home.activation.syncNpmGlobals =
      config.lib.dag.entryAfter [ "writeBoundary" ] ''
        # Ensure node/npm are on PATH for postinstall scripts spawned by npm
        export PATH="${cfg.nodePackage}/bin:${pkgs.git}/bin:$PATH"

        NPM_PREFIX="${cfg.npmPrefix}"
        DECLARED="$HOME/.config/harnix/npm-names.json"
        SPECS="$HOME/.config/harnix/npm-specs.json"

        $DRY_RUN_CMD mkdir -p "$NPM_PREFIX"

        echo "harnix: Syncing npm global packages..."

        # Currently installed package names (exclude builtins: npm, corepack)
        INSTALLED=$(${npm} --prefix="$NPM_PREFIX" list -g --depth=0 --json 2>/dev/null \
          | ${jq} -r '[.dependencies // {} | keys[] | select(. != "npm" and . != "corepack")]') \
          || INSTALLED="[]"

        # Packages to install: names in declared but not in installed
        # Map back to full install specs (with version pins) for npm install
        TO_INSTALL=$(${jq} -n \
          --argjson declared "$(cat "$DECLARED")" \
          --argjson installed "$INSTALLED" \
          --argjson specs "$(cat "$SPECS")" \
          '
            ($declared - $installed) as $missing |
            if ($missing | length) == 0 then empty
            else
              $missing[] as $name |
              ($specs[] | select(. == $name or startswith($name + "@")))
            end
          ' -r) || true

        # Packages to remove: installed but not in declared list
        TO_REMOVE=$(${jq} -n \
          --argjson declared "$(cat "$DECLARED")" \
          --argjson installed "$INSTALLED" \
          '($installed - $declared) | .[]' -r) || true

        if [ -n "$TO_INSTALL" ]; then
          echo "$TO_INSTALL" | while IFS= read -r pkg; do
            echo "harnix: Installing $pkg"
            $DRY_RUN_CMD ${npm} --prefix="$NPM_PREFIX" install -g "$pkg" \
              || echo "harnix: WARNING: Failed to install $pkg"
          done
        fi

        if [ -n "$TO_REMOVE" ]; then
          echo "$TO_REMOVE" | while IFS= read -r pkg; do
            echo "harnix: Removing $pkg"
            $DRY_RUN_CMD ${npm} --prefix="$NPM_PREFIX" uninstall -g "$pkg" \
              || echo "harnix: WARNING: Failed to remove $pkg"
          done
        fi

        echo "harnix: npm sync complete."
      '';

    # ── Activation: sync bun globals ────────────────────────
    home.activation.syncBunGlobals = lib.mkIf cfg.enableBun
      (config.lib.dag.entryAfter [ "writeBoundary" ] ''
        # Ensure bun/node are on PATH for postinstall scripts
        export PATH="${cfg.bunPackage}/bin:${cfg.nodePackage}/bin:${pkgs.git}/bin:$PATH"

        DECLARED="$HOME/.config/harnix/bun-names.json"
        SPECS="$HOME/.config/harnix/bun-specs.json"
        BUN_GLOBAL_DIR="${cfg.bunGlobalDir}"

        DECLARED_COUNT=$(${jq} 'length' "$DECLARED")

        # Get currently installed bun globals by reading the global node_modules dir.
        # bun has no "bun pm ls -g", so we inspect the filesystem directly.
        if [ -d "$BUN_GLOBAL_DIR/node_modules" ]; then
          INSTALLED=$(${ls} -1 "$BUN_GLOBAL_DIR/node_modules" 2>/dev/null \
            | while IFS= read -r entry; do
                if [ "''${entry#@}" != "$entry" ]; then
                  # Scoped package: list subdirectories as @scope/pkg
                  ${ls} -1 "$BUN_GLOBAL_DIR/node_modules/$entry" 2>/dev/null \
                    | while IFS= read -r sub; do
                        echo "$entry/$sub"
                      done
                elif [ "$entry" != ".bin" ] && [ "$entry" != ".cache" ] && [ "$entry" != ".package-lock.json" ]; then
                  echo "$entry"
                fi
              done \
            | ${jq} -R 'select(length > 0)' | ${jq} -s '.')
        else
          INSTALLED="[]"
        fi

        if [ "$DECLARED_COUNT" -eq 0 ] && [ "$INSTALLED" = "[]" ]; then
          echo "harnix: No bun globals declared, skipping."
        else
          echo "harnix: Syncing bun global packages..."

          TO_INSTALL=$(${jq} -n \
            --argjson declared "$(cat "$DECLARED")" \
            --argjson installed "$INSTALLED" \
            --argjson specs "$(cat "$SPECS")" \
            '
              ($declared - $installed) as $missing |
              if ($missing | length) == 0 then empty
              else
                $missing[] as $name |
                ($specs[] | select(. == $name or startswith($name + "@")))
              end
            ' -r) || true

          TO_REMOVE=$(${jq} -n \
            --argjson declared "$(cat "$DECLARED")" \
            --argjson installed "$INSTALLED" \
            '($installed - $declared) | .[]' -r) || true

          if [ -n "$TO_INSTALL" ]; then
            echo "$TO_INSTALL" | while IFS= read -r pkg; do
              echo "harnix: [bun] Installing $pkg"
              $DRY_RUN_CMD ${bun} add -g "$pkg" \
                || echo "harnix: WARNING: Failed to install $pkg"
            done
          fi

          if [ -n "$TO_REMOVE" ]; then
            echo "$TO_REMOVE" | while IFS= read -r pkg; do
              echo "harnix: [bun] Removing $pkg"
              $DRY_RUN_CMD ${bun} remove -g "$pkg" \
                || echo "harnix: WARNING: Failed to remove $pkg"
            done
          fi

          echo "harnix: bun sync complete."
        fi
      '');
  };
}
