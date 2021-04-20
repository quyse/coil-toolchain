{ pkgs }:
rec {
  llvm11 = { ... }@args: import ./llvm11.nix ({
    inherit pkgs utils;
  } // args);
  llvm12 = { ... }@args: import ./llvm12.nix ({
    inherit pkgs utils;
  } // args);

  llvm = llvm12;

  libs = import ./libs.nix;

  utils = import ./utils.nix {
    inherit pkgs;
  };

  windows = { ... }@args: import ./windows ({
    inherit pkgs fixeds;
  } // args);

  fixeds = builtins.fromJSON (builtins.readFile ./fixeds.json);
}
