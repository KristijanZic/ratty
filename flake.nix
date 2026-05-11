{
  description = "A GPU-rendered terminal emulator that supports inline 3D graphics";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      crane,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          lib,
          ...
        }:
        let
          craneLib = crane.mkLib pkgs;

          buildInputs =
            with pkgs;
            [
              vulkan-loader
              libx11
              libxcursor
              libxi
              libxrandr
              wayland
              libxkbcommon
              fontconfig
            ]
            ++ lib.optionals stdenv.isDarwin [
              darwin.apple_sdk.frameworks.Cocoa
              darwin.apple_sdk.frameworks.AppKit
              darwin.apple_sdk.frameworks.CoreGraphics
              rustPlatform.bindgenHook
            ];

          nativeBuildInputs = with pkgs; [
            pkg-config
            makeWrapper
            copyDesktopItems
          ];

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;

          src = craneLib.cleanCargoSource ./.;

          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src buildInputs nativeBuildInputs;
          };

          ratty = craneLib.buildPackage {
            inherit
              src
              cargoArtifacts
              buildInputs
              nativeBuildInputs
              ;

            desktopItems = [
              (pkgs.makeDesktopItem {
                name = "ratty";
                desktopName = "Ratty";
                comment = "A GPU-rendered terminal emulator with inline 3D graphics";
                exec = "ratty";
                terminal = false;
                categories = [ "System" "TerminalEmulator" "Utility" ];
                icon = "ratty";
              })
            ];

            doCheck = false;
            postInstall = pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              install -Dm644 ${./website/assets/images/ratty-logo.png} $out/share/icons/hicolor/512x512/apps/ratty.png

              wrapProgram $out/bin/ratty \
                --prefix LD_LIBRARY_PATH : ${LD_LIBRARY_PATH}
            '';
          };
        in
        {
          packages = {
            default = ratty;
            ratty = ratty;
          };

          devShells.default = craneLib.devShell {
            inputsFrom = [ ratty ];

            inherit LD_LIBRARY_PATH;

            packages = with pkgs; [
              rust-analyzer
            ];
          };
        };

      flake = {
        homeManagerModules.default =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            cfg = config.programs.ratty;
            tomlFormat = pkgs.formats.toml { };
          in
          {
            options.programs.ratty = {
              enable = lib.mkEnableOption "Ratty, a GPU-rendered terminal emulator";

              package = lib.mkOption {
                type = lib.types.package;
                default = self.packages.${pkgs.stdenv.hostPlatform.system}.ratty;
                defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.ratty";
                description = "The ratty package to install.";
              };

              settings = lib.mkOption {
                type = tomlFormat.type;
                default = { };
                description = ''
                  Configuration written to $XDG_CONFIG_HOME/ratty/ratty.toml.
                  See the ratty repository for the default configuration options.
                '';
                example = lib.literalExpression ''
                  {
                    window = {
                      opacity = 0.8;
                    };
                    shell = {
                      program = "bash";
                    };
                  }
                '';
              };
            };

            config = lib.mkIf cfg.enable {
              home.packages = [ cfg.package ];

              xdg.configFile."ratty/ratty.toml" = lib.mkIf (cfg.settings != { }) {
                source = tomlFormat.generate "ratty.toml" cfg.settings;
              };
            };
          };

        nixosModules.default =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            cfg = config.programs.ratty;
            tomlFormat = pkgs.formats.toml { };
          in
          {
            options.programs.ratty = {
              enable = lib.mkEnableOption "Ratty, a GPU-rendered terminal emulator";

              package = lib.mkOption {
                type = lib.types.package;
                default = self.packages.${pkgs.stdenv.hostPlatform.system}.ratty;
                defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.ratty";
                description = "The ratty package to install in the system environment.";
              };

              settings = lib.mkOption {
                type = tomlFormat.type;
                default = { };
                description = ''
                  Configuration written to /etc/ratty/ratty.toml.
                  Note: Defining settings here will wrap the ratty binary to use the system configuration by default.
                '';
                example = lib.literalExpression ''
                  {
                    window = {
                      opacity = 0.8;
                    };
                    shell = {
                      program = "bash";
                    };
                  }
                '';
              };
            };

            config = lib.mkIf cfg.enable {
              environment.systemPackages = [
                (
                  if cfg.settings == { } then
                    cfg.package
                  else
                    pkgs.symlinkJoin {
                      name = "ratty-system-wrapped";
                      paths = [ cfg.package ];
                      nativeBuildInputs = [ pkgs.makeWrapper ];
                      postBuild = ''
                        rm $out/bin/ratty
                        makeWrapper ${cfg.package}/bin/ratty $out/bin/ratty \
                          --add-flags "--config-file /etc/ratty/ratty.toml"
                      '';
                    }
                )
              ];

              environment.etc."ratty/ratty.toml" = lib.mkIf (cfg.settings != { }) {
                source = tomlFormat.generate "ratty.toml" cfg.settings;
              };
            };
          };
      };
    };
}
