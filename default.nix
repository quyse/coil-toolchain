{ pkgsFun ? import <nixpkgs>
, pkgs ? pkgsFun {}
}:
rec {
  llvm11 = { ... }@args: import ./llvm.nix ({
    inherit pkgs utils;
    llvmVersion = "11";
  } // args);
  llvm12 = { ... }@args: import ./llvm.nix ({
    inherit pkgs utils;
    llvmVersion = "12";
  } // args);

  llvm = llvm12;

  gcc = { ... }@args: import ./gcc.nix ({
    inherit pkgs utils;
  } // args);

  libs = import ./libs.nix;

  utils = import ./utils.nix {
    inherit pkgs fixeds;
  };

  windows = { ... }@args: import ./windows ({
    inherit pkgs fixeds;
  } // args);

  fixeds = pkgs.lib.importJSON ./fixeds.json;

  pkgsLinuxGlibc = pkgsFun {};
  pkgsLinuxMusl = pkgsFun {
    crossSystem = {
      config = "x86_64-unknown-linux-musl";
    };
  };
  pkgsWindowsMingw = pkgsFun {
    crossSystem = {
      config = "x86_64-w64-mingw32";
      libc = "msvcrt";
    };
  };

  touch = {
    llvm11LinuxGlibcCc = (llvm11 {
      pkgs = pkgsLinuxGlibc;
    }).stdenv.cc;
    llvm11LinuxMuslCc = (llvm11 {
      pkgs = pkgsLinuxMusl;
    }).stdenv.cc;
    llvm11WindowsMingwCc = (llvm11 {
      pkgs = pkgsWindowsMingw;
    }).stdenv.cc;
    llvm12LinuxGlibcCc = (llvm12 {
      pkgs = pkgsLinuxGlibc;
    }).stdenv.cc;
    llvm12LinuxMuslCc = (llvm12 {
      pkgs = pkgsLinuxMusl;
    }).stdenv.cc;
    llvm12WindowsMingwCc = (llvm12 {
      pkgs = pkgsWindowsMingw;
    }).stdenv.cc;
    gccLinuxGlibcCc = (gcc {
      pkgs = pkgsLinuxGlibc;
    }).stdenv.cc;
    gccWindowsMingwCc = (gcc {
      pkgs = pkgsWindowsMingw;
    }).stdenv.cc;
    initialDisk = (windows {}).initialDisk {};
  };
}
