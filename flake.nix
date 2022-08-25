{
  description = "plutus-scripts";
  inputs.haskellNix.url = "github:input-output-hk/haskell.nix";
  inputs.nixpkgs.follows = "haskellNix/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.iohk-nix.url = "github:input-output-hk/iohk-nix";
  outputs = { self, nixpkgs, flake-utils, haskellNix, iohk-nix }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system:
    let
      overlays = [
        iohk-nix.overlays.crypto
        haskellNix.overlay
        (final: prev: {
          # This overlay adds our project to pkgs
          plutus-scripts =
            final.haskell-nix.project' {
              src = ./.;
              compiler-nix-name = "ghc8107";
              # This is used by `nix develop .` to open a shell for use with
              # `cabal`, `hlint` and `haskell-language-server`
              shell.tools = {
                cabal = {};
                hlint = {};
                # hls-haddock-comments-plugin
                haskell-language-server = {
                  version = "latest";
                  cabalProject = ''
                    packages: .
                    package haskell-language-server
                      flags: -haddockComments
                  '';
                };
              };
              # Non-Haskell shell tools go here
              shell.buildInputs = with pkgs; [
                nixpkgs-fmt
              ];

              shell.inputsFrom = [ pkgs.libsodium-vrf ];
              shell.nativeBuildInputs = with pkgs;
                [
                  libsodium-vrf
                ];

              # This adds `js-unknown-ghcjs-cabal` to the shell.
              # shell.crossPlatforms = p: [p.ghcjs];
            };
        })
      ];
      pkgs = import nixpkgs { inherit system overlays; inherit (haskellNix) config; };
      flake = pkgs.plutus-scripts.flake {
        # This adds support for `nix build .#js-unknown-ghcjs-cabal:plutus-scripts:exe:plutus-scripts`
        # crossPlatforms = p: [p.ghcjs];
      };
    in flake // {
      # Built by `nix build .`
      defaultPackage = flake.packages."plutus-scripts:exe:plutus-scripts";
    });
}

