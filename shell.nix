# lorri doesn't work with flake-compat, so we use a nix-shell shell.nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.entr

    # keep this line if you use bash
    pkgs.bashInteractive
  ];
}
