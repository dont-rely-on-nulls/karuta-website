{
  description = "Don't Rely on Nulls — Website";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      devenv,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        { pkgs, system, ... }:
        let
          customEmacs = (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages (
            epkgs:
            with epkgs.melpaPackages;
            [
              citeproc
              htmlize
              ox-rss
            ]
            ++ (with epkgs.elpaPackages; [
              org
              org-roam
            ])
          );
        in
        {
          packages = {
            default = pkgs.stdenvNoCC.mkDerivation {
              name = "site";
              src = pkgs.lib.cleanSource ./.;
              buildInputs = [
                customEmacs
                pkgs.gnumake
              ];
              IS_CI = "1";
              ENVIRONMENT = "prod";
              LANG = "en_US.UTF-8";
              buildPhase = ''
                export HOME="$(mktemp -d)"
                mkdir -p ~/.emacs.d
                make build
              '';
              installPhase = ''
                mkdir -p $out
                cp -r public/* $out/
              '';
            };
          };

          devShells = {
            ci = pkgs.mkShell {
              IS_CI = "1";
              LANG = "en_US.UTF-8";
              buildInputs = [
                customEmacs
                pkgs.gnumake
              ];
            };

            default = devenv.lib.mkShell {
              inherit inputs pkgs;
              modules = [
                (
                  { pkgs, lib, ... }:
                  {
                    packages = [
                      pkgs.gnumake
                      pkgs.python3
                    ];

                    env = {
                      ENVIRONMENT = "dev";
                      LANG = "en_US.UTF-8";
                    };

                    scripts = {
                      build.exec = "make build";
                      clean.exec = "make clean";
                      serve.exec = "make serve";
                    };

                    enterShell = ''
                      echo "DrN Website development shell ready."
                    '';
                  }
                )
              ];
            };
          };
        };

      flake = { };
    };
}
