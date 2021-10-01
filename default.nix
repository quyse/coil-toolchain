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

  refreshFixedsScript = pkgs.writeScript "refresh_fixeds" ''
    PATH=$PATH:${pkgs.jq}/bin:${pkgs.nodejs}/bin NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt node ${./refresh_fixeds.js}
  '';

  autoUpdateFixedsScript = fixedsFile: pkgs.writeScript "auto_update_fixeds" ''
    set -e
    cp --no-preserve=mode ${fixedsFile} ./fixeds.json
    ${refreshFixedsScript}
    if ! cmp -s ${fixedsFile} ./fixeds.json
    then
      echo 'update fixeds' > .git-commit
    fi
  '';

  autoUpdateScript = autoUpdateFixedsScript ./fixeds.json;

  mkDummy = pkgs: pkgs.stdenv.mkDerivation {
    name = "dummy";
    phases = ["buildPhase"];
    buildPhase = ''
      touch $out
    '';
  };

  touch = {
    llvm11LinuxGlibc = mkDummy (llvm11 {
      pkgs = pkgsLinuxGlibc;
    });
    llvm11LinuxMusl = mkDummy (llvm11 {
      pkgs = pkgsLinuxMusl;
    });
    llvm11WindowsMingw = mkDummy (llvm11 {
      pkgs = pkgsWindowsMingw;
    });
    llvm12LinuxGlibc = mkDummy (llvm12 {
      pkgs = pkgsLinuxGlibc;
    });
    llvm12LinuxMusl = mkDummy (llvm12 {
      pkgs = pkgsLinuxMusl;
    });
    llvm12WindowsMingw = mkDummy (llvm12 {
      pkgs = pkgsWindowsMingw;
    });
    gccLinuxGlibc = mkDummy (gcc {
      pkgs = pkgsLinuxGlibc;
    });
    gccWindowsMingw = mkDummy (gcc {
      pkgs = pkgsWindowsMingw;
    });

    initialDisk = (windows {}).initialDisk {};

    stuffd = utils.stuffd {
      handlers = [];
    };

    inherit refreshFixedsScript autoUpdateScript;
  };
}
