rec {
  stdenvHostUseLLVM = stdenv: stdenv.override {
    hostPlatform = stdenv.hostPlatform // {
      useLLVM = true;
    };
  };
  stdenvTargetUseLLVM = stdenv: stdenv.override {
    targetPlatform = stdenv.targetPlatform // {
      useLLVM = true;
    };
  };

  stdenvPlatformFixes = stdenv:
    stdenv.overrideDerivation (s: s // {
      mkDerivation = args: s.mkDerivation (args // {
        hardeningDisable = if s.hostPlatform.isWindows then ["all"] else args.hardeningDisable or [];
      });
    });

  unNixElf = {
    x86_64 = "patchelf --remove-rpath --set-interpreter /lib64/ld-linux-x86-64.so.2";
  };

  # stdenv adapter, forcing glibc version
  stdenvForceGlibcVersion = { pkgs, arch, version }: let
    repo = pkgs.fetchFromGitHub {
      owner = "wheybags";
      repo = "glibc_version_header";
      rev = "60d54829f34f21dc440126ad5630e6a9789a48b2";
      sha256 = "1zh2zv2z0xaqq27236hrinqdazddvqzg15fsy18pdmk90ifiz20w";
    };
    libcxxForceGlibcVersionHeader = pkgs.writeText "libcxx_force_glibc_version.h" ''
      #define _LIBCPP_GLIBC_PREREQ(a, b) ((${pkgs.lib.versions.major version} << 16) + ${pkgs.lib.versions.minor version} >= ((a) << 16) + (b))
    '';
  in stdenv:
    stdenv.overrideDerivation (s: s // {
      mkDerivation = args: s.mkDerivation (args // {
        NIX_CFLAGS_COMPILE =
          "${toString (args.NIX_CFLAGS_COMPILE or "")} " +
          "-include ${repo}/version_headers/${arch}/force_link_glibc_${version}.h " +
          "-include ${libcxxForceGlibcVersionHeader}";
      });
    });
}
