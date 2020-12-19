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
        hardeningDisable = if stdenv.hostPlatform.isWindows then ["all"] else args.hardeningDisable or [];
      });
    });

  unNixElf = {
    x86_64 = "patchelf --remove-rpath --set-interpreter /lib64/ld-linux-x86-64.so.2";
  };
}
