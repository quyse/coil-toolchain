{ pkgs
, utils
, hostStdenvAdapter ? pkgs.lib.id
}:
let
  stdenvHostFlags = stdenv: stdenv.override {
    hostPlatform = stdenv.hostPlatform // {
      isStatic = true;
    };
  };

in rec {
  hostStdenv = pkgs.lib.pipe pkgs.gcc11Stdenv [
    utils.stdenvFunctionSections
    stdenvHostFlags
    utils.stdenvPlatformFixes
    pkgs.stdenvAdapters.propagateBuildInputs
    hostStdenvAdapter
  ];
  stdenv = hostStdenv;
}
