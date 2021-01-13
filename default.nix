rec {
  llvm11 = import ./llvm11.nix;

  llvm = llvm11;

  libs = import ./libs.nix;

  utils = import ./utils.nix;

  windows = { ... }@args: import ./platforms/windows ({
    inherit fixeds;
  } // args);

  fixeds = builtins.fromJSON (builtins.readFile ./fixeds.json);
}
