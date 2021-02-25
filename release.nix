{ pkgs }:
let
  root = import ./. {
    inherit pkgs;
  };
  llvm11 = root.llvm11 {};
  windows = root.windows {};
in {
  inherit root;
  touch = {
    llvm11cc = llvm11.stdenv.cc;
    initialDisk = windows.initialDisk {};
  };
}
