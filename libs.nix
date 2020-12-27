{ stdenv }:
let
  overrides = {
    inherit stdenv;
  };
in rec {
  overlay = self: super: {
    # separate to not affect the rest of nixpkgs
    coil = rec {
      zlib = self.callPackage ./libs/zlib-ng overrides;

      boost = super.boost.override (overrides // {
        enableShared = false;
        enableStatic = true;
        toolset = null;
        inherit zlib;
      });
    };
  };
}
