{ stdenv }:
let
  overrides = {
    inherit stdenv;
  };
in rec {
  overlay = self: super: {
    # separate to not affect the rest of nixpkgs
    coil = rec {
      boost = (super.boost17x.override (overrides // {
        enableShared = false;
        enableStatic = true;
        toolset = null;
      })).overrideAttrs (attrs: {
        patches = (attrs.patches or [])
          ++ stdenv.lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [./libs/boost/cross.patch]
          ++ stdenv.lib.optionals (builtins.compareVersions attrs.version "1.75" < 0) [./libs/boost/libcxx.patch]
        ;
        # disarm strange RANLIB line
        postFixup = builtins.replaceStrings ["$RANLIB"] ["true"] (attrs.postFixup or "");
      });
    };
  };
}
