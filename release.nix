{ pkgsFun }:
let
  pkgs = pkgsFun {};
  root = import ./. {
    inherit pkgs;
  };
  llvm11Linux = root.llvm11 {};
  llvm11Windows = root.llvm11 {
    pkgs = pkgsFun {
      crossSystem = {
        config = "x86_64-w64-mingw32";
        libc = "msvcrt";
      };
    };
  };
  llvm12Linux = root.llvm12 {};
  llvm12Windows = root.llvm12 {
    pkgs = pkgsFun {
      crossSystem = {
        config = "x86_64-w64-mingw32";
        libc = "msvcrt";
      };
    };
  };
  windows = root.windows {};


in {
  inherit root;
  touch = {
    llvm11LinuxCc = llvm11Linux.stdenv.cc;
    llvm11WindowsCc = llvm11Windows.stdenv.cc;
    llvm12LinuxCc = llvm12Linux.stdenv.cc;
    llvm12WindowsCc = llvm12Windows.stdenv.cc;
    initialDisk = windows.initialDisk {};
  };
}
