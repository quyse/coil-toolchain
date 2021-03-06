{ pkgs
, utils
, hostStdenvAdapter ? pkgs.lib.id
}:
let
  patchMingwLibc = libc: if libc != null && pkgs.lib.hasPrefix "mingw-w64" libc.name
    then let
      mingw_w64 = libc.overrideAttrs (attrs: rec {
        version = "9.0.0";
        src = pkgs.fetchurl {
          url = "mirror://sourceforge/mingw-w64/mingw-w64-v${version}.tar.bz2";
          sha256 = "10a15bi4lyfi0k0haj0klqambicwma6yi7vssgbz8prg815vja8r";
        };
        buildInputs = [mingw_w64_headers];
      });
      mingw_w64_headers = pkgs.stdenvNoCC.mkDerivation {
        name = "${mingw_w64.name}-headers";
        inherit (mingw_w64) src meta;
        preConfigure = ''
          cd mingw-w64-headers
        '';
      };
    in mingw_w64
    else libc;

in rec {
  hostLibraries = (pkgs.llvmPackages_11.override {
    stdenv = hostStdenv;
    buildLlvmTools = buildTools;
  }).libraries.extend (self: super: {
    enableShared = false;
    libcxx = super.libcxx.overrideAttrs (attrs: {
      cmakeFlags = (attrs.cmakeFlags or []) ++ [
        "-DLIBCXX_HERMETIC_STATIC_LIBRARY=ON"
      ];
      NIX_CFLAGS_COMPILE = if self.stdenv.hostPlatform.isWindows then "-D_WIN32_WINNT=0x0600" else null;
      patches = (attrs.patches or []) ++ [./libs/libcxx11/override-glibc-prereq.patch];
    });
    libcxxabi = super.libcxxabi.overrideAttrs (attrs: {
      cmakeFlags = (attrs.cmakeFlags or []) ++ [
        "-DLIBCXXABI_USE_COMPILER_RT=ON"
        "-DLIBCXXABI_HERMETIC_STATIC_LIBRARY=ON"
      ];
      NIX_CFLAGS_COMPILE = if self.stdenv.hostPlatform.isWindows then "-D_WIN32_WINNT=0x0600" else null;
    });
    libunwind = super.libunwind.overrideAttrs (attrs: {
      cmakeFlags = (attrs.cmakeFlags or []) ++ [
        "-DLIBUNWIND_USE_COMPILER_RT=ON"
        "-DLIBUNWIND_HERMETIC_STATIC_LIBRARY=ON"
      ];
      NIX_CFLAGS_COMPILE = if self.stdenv.hostPlatform.isWindows then "-D__STDC_FORMAT_MACROS=1 -D_WIN32_WINNT=0x0600" else null;
    });
  });

  buildTools = (pkgs.buildPackages.llvmPackages_11.override {
    stdenv = buildStdenv;
    targetLlvmLibraries = hostLibraries;
    wrapCCWith = args: pkgs.buildPackages.wrapCCWith (args // {
      stdenvNoCC = utils.stdenvTargetFlags pkgs.buildPackages.stdenvNoCC;
    });
    preLibcCrossHeaders = patchMingwLibc pkgs.preLibcCrossHeaders;
    wrapBintoolsWith =
      { libc ?
        if pkgs.buildPackages.stdenv.targetPlatform != pkgs.buildPackages.stdenv.hostPlatform
          then patchMingwLibc pkgs.buildPackages.libcCross
          else pkgs.buildPackages.stdenv.cc.libc
      , ...
      } @ args:
      pkgs.buildPackages.wrapBintoolsWith (args // {
        stdenvNoCC = utils.stdenvTargetFlags pkgs.buildPackages.stdenvNoCC;
        inherit libc;
      });
  }).tools.extend (self: super: {
    clang-unwrapped = super.clang-unwrapped.overrideAttrs (attrs: {
      patches = (attrs.patches or []) ++ [./libs/clang11/static-libunwind.patch];
    });
  });

  hostStdenv = pkgs.lib.pipe (pkgs.overrideCC pkgs.stdenv buildTools.clangUseLLVM) [
    utils.stdenvFunctionSections
    utils.stdenvHostFlags
    utils.stdenvPlatformFixes
    pkgs.stdenvAdapters.propagateBuildInputs
    hostStdenvAdapter
  ];
  buildStdenv = utils.stdenvTargetFlags pkgs.buildPackages.stdenv;
  stdenv = hostStdenv;
}
