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
      icu = super.icu.override overrides;
      # TODO: libiconv for boost
      boost = (super.boost17x.override (overrides // {
        enableShared = false;
        enableStatic = true;
        toolset = null;
        inherit expat zlib bzip2 icu;
      })).overrideAttrs (attrs: {
        patches = (attrs.patches or [])
          ++ self.lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [./libs/boost/cross.patch]
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
      curl = (super.curlMinimal.override (overrides // {
        inherit openssl zlib;
        http2Support = false;
        idnSupport = false;
        scpSupport = false;
        gssSupport = false;
        brotliSupport = false;
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
