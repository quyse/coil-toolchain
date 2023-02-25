{ pkgs
, lib ? pkgs.lib
, fixeds
}:
rec {
  stdenvPlatformFixes = overrideMkDerivation (stdenv: args: {
    hardeningDisable = if stdenv.hostPlatform.isWindows then ["all"] else args.hardeningDisable or [];
  } // (if stdenv.hostPlatform.isWindows && stdenv.hostPlatform.useLLVM or false then {
    RC = "${stdenv.cc.bintools.targetPrefix}llvm-rc";
  } else {}));

  unNixElf = {
    x86_64 = "patchelf --remove-rpath --set-interpreter /lib64/ld-linux-x86-64.so.2";
  };

  # stdenv adapter, forcing glibc version
  stdenvForceGlibcVersion = { arch, version }: let
    repo = pkgs.fetchgit {
      inherit (fixeds.fetchgit."https://github.com/wheybags/glibc_version_header.git") url rev sha256;
    };
    libcxxForceGlibcVersionHeader = pkgs.writeText "libcxx_force_glibc_version.h" ''
      #define _LIBCPP_GLIBC_PREREQ(a, b) ((${lib.versions.major version} << 16) + ${lib.versions.minor version} >= ((a) << 16) + (b))
    '';
  in overrideMkDerivation (stdenv: args: {
    NIX_CFLAGS_COMPILE =
      "${toString (args.NIX_CFLAGS_COMPILE or "")}" +
      " -include ${repo}/version_headers/${arch}/force_link_glibc_${version}.h" +
      " -include ${libcxxForceGlibcVersionHeader}";
  });

  overrideMkDerivation = f: stdenv:
    stdenv.overrideDerivation (s: s // {
      mkDerivation = fnOrArgs: if builtins.isFunction fnOrArgs
        then s.mkDerivation (self: let args = fnOrArgs self; in args // f s args)
        else s.mkDerivation (fnOrArgs // f s fnOrArgs);
    });

  # easy-to-use stdenv adapter for all sorts of compatibility
  stdenvForceCompatibility = { reqs }: stdenv: let
    minDep = dep: version: deps: let
      curVersion = deps.${dep} or null;
      in if curVersion == null || builtins.compareVersions version curVersion < 0
        then deps // {
          "${dep}" = version;
        }
        else deps;
    minGlibc = minDep "glibc";
    f = req: {
      "ubuntu-12.04" = minGlibc "2.15";
      "ubuntu-14.04" = minGlibc "2.19";
      "ubuntu-16.04" = minGlibc "2.23";
      "ubuntu-18.04" = minGlibc "2.27";
    }.${req} or (abort "unknown compatibility requirement: ${req}");
    deps = lib.foldr f {} reqs;
    glibcReq = deps.glibc or null;
    glibcAdapter = stdenvForceGlibcVersion {
      arch = if stdenv.hostPlatform.isx86_64 then "x64" else "x86";
      version = glibcReq;
    };
    adapters =
      lib.optional (stdenv.hostPlatform.libc == "glibc" && stdenv.hostPlatform.isx86 && glibcReq != null) glibcAdapter;
  in lib.pipe stdenv adapters;

  fetchGitLfs =
    { repoUrl
    , ref ? null
    , netrcVar ? "GIT_LFS_NETRC"
    }: pointer: let
    info = lib.pipe pointer [
      builtins.readFile
      (lib.splitString "\n")
      (map (builtins.match "([a-z0-9.-]+) (.+)"))
      (builtins.filter (re: re != null))
      (map (re: lib.nameValuePair (builtins.elemAt re 0) (builtins.elemAt re 1)))
      lib.listToAttrs
      (o: assert (o.version == "https://git-lfs.github.com/spec/v1"); o)
    ];
    oidParsed = builtins.match "([a-z0-9]+):(.+)" info.oid;
    outputHashAlgo = builtins.elemAt oidParsed 0;
    outputHash = builtins.elemAt oidParsed 1;
  in pkgs.callPackage ./utils/fetchgitlfs.nix {
    inherit pointer repoUrl ref netrcVar outputHashAlgo outputHash;
    inherit (info) size;
  };

  xml = import ./utils/xml.nix {
    inherit lib;
  };

  inherit (import ./utils/stuff.nix {
    inherit pkgs lib;
  }) stuffd fetchStuff;
}
