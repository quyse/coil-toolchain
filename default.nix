{ pkgs }:
rec {
  llvm11 = import ./llvm11.nix { inherit pkgs; };

  llvm = llvm11;

  libs = import ./libs.nix;

  utils = import ./utils.nix;
}
