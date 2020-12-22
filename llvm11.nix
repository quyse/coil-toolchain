{ pkgs
, hostStdenvAdapter ? pkgs.lib.id
}:
let
  utils = import ./utils.nix;
in rec {
  patchTools = tools: tools.extend (self: super: {
    clang-unwrapped = super.clang-unwrapped.overrideAttrs (attrs: {
      patches = (attrs.patches or []) ++ [./clang11.patch];
    });
  });

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
      patches = (attrs.patches or []) ++ [./libcxx11.patch];
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
  buildTools = patchTools (pkgs.buildPackages.llvmPackages_11.override {
    stdenv = buildStdenv;
    targetLlvmLibraries = hostLibraries;
    wrapCCWith = args: pkgs.buildPackages.wrapCCWith (args // {
      stdenvNoCC = utils.stdenvTargetUseLLVM pkgs.buildPackages.stdenvNoCC;
    });
    wrapBintoolsWith = args: pkgs.buildPackages.wrapBintoolsWith (args // {
      stdenvNoCC = utils.stdenvTargetUseLLVM pkgs.buildPackages.stdenvNoCC;
    });
  }).tools;
  hostStdenv = pkgs.lib.pipe (pkgs.overrideCC pkgs.stdenv buildTools.lldClang) [
    utils.stdenvHostUseLLVM
    utils.stdenvPlatformFixes
    pkgs.stdenvAdapters.propagateBuildInputs
    hostStdenvAdapter
  ];
  buildStdenv = utils.stdenvTargetUseLLVM pkgs.buildPackages.stdenv;
  stdenv = hostStdenv;
}
