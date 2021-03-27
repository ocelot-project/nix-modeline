{
  description = "Nix builder info in your Emacs modeline";

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
        version = "1.0.0";
        src = self;
        buildInputs = [ pkgs.emacs pkgs.entr ];
        recipe = pkgs.writeText "recipe" ''
          (nix-modeline :fetcher git :url "localhost")
        '';
        prePatch = ''
          substituteInPlace nix-modeline.el \
          --replace 'defcustom nix-modeline-entr-command "entr"' \
          'defcustom nix-modeline-entr-command "${pkgs.entr}/bin/entr"'
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
