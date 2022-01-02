{ stdenv }:
let
  overrides = {
    inherit stdenv;
  };
in rec {
  overlay = self: super: {
    # separate to not affect the rest of nixpkgs
    coil = rec {
      expat = super.expat.override overrides;
      zlib = self.callPackage ./libs/zlib-ng overrides;
      bzip2 = super.bzip2.override overrides;
      libiconv = (super.libiconvReal.override overrides).overrideAttrs (attrs: {
        postPatch = ''
          sed -ie 's?OBJECTS_RES_yes = iconv.res?OBJECTS_RES_yes =?' src/Makefile.in
          sed -ie 's?OBJECTS_RES_yes = libiconv.res.lo?OBJECTS_RES_yes =?' lib/Makefile.in
        '';
      });
      icu = super.icu.override overrides;
      boost = (super.boost17x.override (overrides // {
        enableShared = false;
        enableStatic = true;
        inherit expat zlib bzip2 libiconv icu;
      })).overrideAttrs (attrs: {
        patches = (attrs.patches or [])
          ++ self.lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform && builtins.compareVersions attrs.version "1.77" < 0) [./libs/boost/cross.patch]
          ++ self.lib.optionals (builtins.compareVersions attrs.version "1.75" < 0) [./libs/boost/libcxx.patch]
        ;
        # disarm strange RANLIB line
        postFixup = builtins.replaceStrings ["$RANLIB"] ["true"] (attrs.postFixup or "");
      });
      openssl = (super.openssl.override overrides).overrideAttrs (attrs: {
        # https://github.com/openssl/openssl/blob/master/INSTALL.md
        configureFlags = self.lib.filter (x: x != "shared") attrs.configureFlags ++ [
          "no-dso"
          "no-engine"
          "no-stdio"
        ];
        patches = []; # assuming all patches are about CA paths
        postInstall = ''
          touch $out/bin/c_rehash # fake file for postInstall to not break
        '' + (attrs.postInstall or "") + ''
          rm $bin/bin/c_rehash # remove fake file (moved since)
        '';
      });
      brotli = super.brotli.override overrides;
      curl = (super.curlMinimal.override (overrides // {
        inherit openssl zlib;
        zlibSupport = true;
        http2Support = false;
        idnSupport = false;
        scpSupport = false;
        gssSupport = false;
      })).overrideAttrs (attrs: {
        configureFlags =
        (if stdenv.hostPlatform.isWindows
          then self.lib.filter (x: !(self.lib.hasPrefix "--with-ssl=" x)) attrs.configureFlags ++ ["--with-winssl"]
          else attrs.configureFlags
        ) ++
        [
          "--disable-shared"
          "--enable-static"
        ];
        # fix linking static openssl
        LIBS = self.lib.optionalString stdenv.hostPlatform.isLinux "-pthread";
      });
    };
  };
}
