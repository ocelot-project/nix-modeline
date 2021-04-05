{
  description = "Nix builder info in your Emacs modeline";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-20.09";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat }:
  flake-utils.lib.eachDefaultSystem (system:
  let pkgs = nixpkgs.legacyPackages.${system}; in rec {
    packages.nix-modeline =
      pkgs.stdenv.mkDerivation {
        pname = "nix-modeline";
        version = "1.1.0";
        src = self;
        buildInputs = [ pkgs.emacs ];
        recipe = pkgs.writeText "recipe" ''
          (nix-modeline :fetcher git :url "localhost")
        '';
        buildPhase = ''
          emacs -L . --batch -f batch-byte-compile *.el
        '';
        installPhase = ''
          mkdir -p $out/share/emacs/site-lisp
          install *.el* $out/share/emacs/site-lisp
        '';
      };

      defaultPackage = packages.nix-modeline;

      overlays = import ./overlay.nix (flakePackages: pkgs);
  });
}
