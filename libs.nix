{ overrides ? {} }:
rec {
  overlay = self: super: {
    # separate to not affect the rest of nixpkgs
    coil = rec {
      zlib = super.zlib.override (overrides // {
        shared = false;
        static = true;
        splitStaticOutput = false;
      });

      boost = super.boost.override (overrides // {
        enableShared = false;
        enableStatic = true;
        toolset = null;
        inherit zlib;
      });
    };
  };
}
