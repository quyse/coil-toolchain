{ pkgs
, utils
, hostStdenvAdapter ? pkgs.lib.id
, llvmVersion
}:
let
  patchMingwLibc = libc: if libc != null && pkgs.lib.hasPrefix "mingw-w64" libc.name
    then let
      mingw_w64 = libc.overrideAttrs (attrs: rec {
        version = "10.0.0";
        src = pkgs.fetchurl {
          url = "mirror://sourceforge/mingw-w64/mingw-w64-v${version}.tar.bz2";
          hash = "sha256-umtDCu1yxjo3aFMfaj/8Kw/eLFejslFFDc9ImolPCJQ=";
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

  stdenvHostFlags = stdenv: stdenv.override {
    hostPlatform = stdenv.hostPlatform // {
      useLLVM = true;
      linker = "lld";
      isStatic = true;
    };
  };
  stdenvTargetFlags = stdenv: stdenv.override {
    targetPlatform = stdenv.targetPlatform // {
      useLLVM = true;
      linker = "lld";
      isStatic = true;
    };
  };

in rec {
  hostLibraries = (pkgs."llvmPackages_${llvmVersion}".override {
    stdenv = hostStdenv;
    buildLlvmTools = buildTools;
  }).libraries.extend (self: super: {
    enableShared = false;
    compiler-rt = (super.compiler-rt.override {
      libxcrypt = ""; # hack: disable libxcrypt
    }).overrideAttrs (attrs: {
      cmakeFlags = (attrs.cmakeFlags or []) ++ [
        "-DCOMPILER_RT_BUILD_MEMPROF=OFF" # fails for some reason
        "-DCOMPILER_RT_BUILD_ORC=OFF" # fails for some reason
      ];
    });
    libcxx = super.libcxx.overrideAttrs (attrs: {
      cmakeFlags = (attrs.cmakeFlags or []) ++ [
        "-DLIBCXX_HERMETIC_STATIC_LIBRARY=ON"
      ];
      NIX_CFLAGS_COMPILE = if self.stdenv.hostPlatform.isWindows then "-D_WIN32_WINNT=0x0600" else null;
      patches = (attrs.patches or []) ++ [
        (./. + "/libs/libcxx${llvmVersion}/override-glibc-prereq.patch")
      ];
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

  buildTools = (pkgs.buildPackages."llvmPackages_${llvmVersion}".override {
    stdenv = buildStdenv;
    targetLlvmLibraries = hostLibraries;
    wrapCCWith = args: pkgs.buildPackages.wrapCCWith (args // {
      stdenvNoCC = stdenvTargetFlags pkgs.buildPackages.stdenvNoCC;
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
        stdenvNoCC = stdenvTargetFlags pkgs.buildPackages.stdenvNoCC;
        inherit libc;
      });
  }).tools.extend (self: super: {
    clang-unwrapped = super.clang-unwrapped.overrideAttrs (attrs: {
      patches = (attrs.patches or []) ++ [
        (./. + "/libs/clang${llvmVersion}/static-libunwind.patch")
      ];
    });
  });

  hostStdenv = pkgs.lib.pipe (pkgs.overrideCC pkgs.stdenv buildTools.clangUseLLVM) [
    stdenvHostFlags
    utils.stdenvPlatformFixes
    pkgs.stdenvAdapters.propagateBuildInputs
    hostStdenvAdapter
  ];
  buildStdenv = stdenvTargetFlags pkgs.buildPackages.stdenv;
  stdenv = hostStdenv;
}
