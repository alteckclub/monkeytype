{
  description = "Static, anonymous build of the Monkeytype frontend, packaged for Nix";

  inputs.nixpkgs.url = "nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        # Hash-pinned dependency tree.
        #
        # This must stay bit-reproducible, so no install scripts run here:
        # `--ignore-scripts` only unpacks tarballs. None of the build inputs
        # need them (rolldown/vite ship prebuilt platform bindings), and the
        # original pnpm tree could not be made reproducible at all.
        npm-deps = pkgs.stdenvNoCC.mkDerivation {
          name = "monkeytype-npm-deps";
          src = self;
          nativeBuildInputs = [
            pkgs.nodejs_24
            pkgs.cacert
            pkgs.coreutils
          ];
          dontConfigure = true;
          dontFixup = true;
          installPhase = ''
            runHook preInstall

            export HOME=$TMPDIR/home
            export npm_config_cache=$TMPDIR/npm-cache
            export npm_config_yes=true
            export npm_config_update_notifier=false
            mkdir -p "$HOME"

            cp -r $src $TMPDIR/app
            chmod -R u+w $TMPDIR/app

            cd $TMPDIR/app
            # --legacy-peer-deps mirrors pnpm, which only warns about the
            # vite 8 peer ranges in the dev-only plugin set.
            npm ci --ignore-scripts --legacy-peer-deps --no-audit --no-fund --loglevel=warn

            mkdir -p $out
            cp -a node_modules $out/node_modules

            runHook postInstall
          '';
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-3JB57IutusqPKHGPO4e5BK7JqBCgQ97J1jPSdvpeBMk=";
        };

        monkeytype-frontend = pkgs.stdenvNoCC.mkDerivation {
          name = "monkeytype-frontend";
          src = self;
          nativeBuildInputs = [
            pkgs.nodejs_24
            pkgs.coreutils
          ];
          dontConfigure = true;
          dontFixup = true;

          installPhase = ''
            runHook preInstall

            export HOME=$TMPDIR/home
            export npm_config_cache=$TMPDIR/npm-cache
            export npm_config_update_notifier=false
            # No backend: point the client at a same-origin path so it can
            # never fall back to (or reach) monkeytype's hosted API. Without
            # this the production build bakes in https://api.monkeytype.com.
            export BACKEND_URL=/api
            mkdir -p "$HOME"

            cp -r $src $TMPDIR/app
            chmod -R u+w $TMPDIR/app
            cp -a ${npm-deps}/node_modules $TMPDIR/app/node_modules
            chmod -R u+w $TMPDIR/app/node_modules

            # Store paths are read-only, so the exec bit npm sets on the .bin
            # shims is gone, and their #!/usr/bin/env shebangs have no
            # interpreter here. .bin entries are symlinks: fix the targets.
            for f in $TMPDIR/app/node_modules/.bin/*; do
              target="$(readlink -f "$f")"
              if [ -f "$target" ]; then
                patchShebangs "$target"
                chmod +x "$target"
              fi
            done
            while IFS= read -r -d "" f; do patchShebangs "$f"; done < <(
              find $TMPDIR/app/node_modules -maxdepth 3 -path '*/bin/*' -type f -print0
            )

            cd $TMPDIR/app
            npm run build --legacy-peer-deps

            mkdir -p $out
            # the package root is the site root, so nginx can point at it directly
            cp -a frontend/dist/. $out/

            runHook postInstall
          '';
        };

        default = monkeytype-frontend;
      });
    };
}
