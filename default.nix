{ pkgsFun ? import <nixpkgs>
, pkgs ? pkgsFun {}
}:
rec {
  llvm12 = { ... }@args: import ./llvm.nix ({
    inherit pkgs utils;
    llvmVersion = "12";
  } // args);
  llvm13 = { ... }@args: import ./llvm.nix ({
    inherit pkgs utils;
    llvmVersion = "13";
  } // args);
  llvm14 = { ... }@args: import ./llvm.nix ({
    inherit pkgs utils;
    llvmVersion = "14";
  } // args);

  llvm = llvm13;

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
    PATH=$PATH:${pkgs.jq}/bin:${pkgs.nix-prefetch-git}/bin:${pkgs.nodejs}/bin NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt node ${./refresh_fixeds.js}
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
    llvm12LinuxGlibc = mkDummy (llvm12 {
      pkgs = pkgsLinuxGlibc;
    });
    llvm12LinuxMusl = mkDummy (llvm12 {
      pkgs = pkgsLinuxMusl;
    });
    llvm12WindowsMingw = mkDummy (llvm12 {
      pkgs = pkgsWindowsMingw;
    });
    llvm13LinuxGlibc = mkDummy (llvm13 {
      pkgs = pkgsLinuxGlibc;
    });
    llvm13LinuxMusl = mkDummy (llvm13 {
      pkgs = pkgsLinuxMusl;
    });
    llvm13WindowsMingw = mkDummy (llvm13 {
      pkgs = pkgsWindowsMingw;
    });
    llvm14LinuxGlibc = mkDummy (llvm14 {
      pkgs = pkgsLinuxGlibc;
    });
    llvm14LinuxMusl = mkDummy (llvm14 {
      pkgs = pkgsLinuxMusl;
    });
    llvm14WindowsMingw = mkDummy (llvm14 {
      pkgs = pkgsWindowsMingw;
    });
    gccLinuxGlibc = mkDummy (gcc {
      pkgs = pkgsLinuxGlibc;
    });
    gccWindowsMingw = mkDummy (gcc {
      pkgs = pkgsWindowsMingw;
    });

    initialDisk = (windows {}).initialDisk {};
    inherit (windows {}) makemsix;

    stuffd = utils.stuffd {
      handlers = [];
    };

    inherit refreshFixedsScript autoUpdateScript;
  };

  path = ./.;
}
