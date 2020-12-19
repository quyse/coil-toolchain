{ overrides ? {} }:
rec {
  overlay = self: super: {
    boost = super.boost.override (overrides // {
      enableShared = false;
      enableStatic = true;
    });
    zlib = super.zlib.override (overrides // {
      shared = false;
      static = true;
      splitStaticOutput = false;
    });
  };
}
