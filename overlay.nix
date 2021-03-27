flakePackages: final: prev:
let flake = flakePackages prev; in
{
  nix-modeline = flake;
}
