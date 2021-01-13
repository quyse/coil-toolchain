{ pkgs ? import <nixpkgs> {}
}:
let
  root = import ./.;
  llvm11 = root.llvm11 {
    inherit pkgs;
  };
  windows = root.windows {
    inherit pkgs;
  };
in {
  touch = {
    llvm11cc = llvm11.stdenv.cc;
    inherit (windows) initialDisk;
  };
}
