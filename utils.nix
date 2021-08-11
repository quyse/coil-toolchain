{ pkgs
, fixeds
}:
rec {
  stdenvPlatformFixes = stdenv:
    stdenv.overrideDerivation (s: s // {
      mkDerivation = args: s.mkDerivation (args // {
        hardeningDisable = if s.hostPlatform.isWindows then ["all"] else args.hardeningDisable or [];
      } // (if s.hostPlatform.isWindows && s.hostPlatform.useLLVM or false then {
        RC = "${stdenv.cc.bintools.targetPrefix}llvm-rc";
      } else {}));
    });

  stdenvFunctionSections = stdenv:
    stdenv.overrideDerivation (s: s // {
      mkDerivation = args: s.mkDerivation (args // {
        NIX_CFLAGS_COMPILE = "${toString (args.NIX_CFLAGS_COMPILE or "")} -ffunction-sections";
        NIX_LDFLAGS = "${toString (args.NIX_LDFLAGS or "")} --gc-sections";
      });
    });

  unNixElf = {
    x86_64 = "patchelf --remove-rpath --set-interpreter /lib64/ld-linux-x86-64.so.2";
  };

  # stdenv adapter, forcing glibc version
  stdenvForceGlibcVersion = { arch, version }: let
    repo = pkgs.fetchgit {
      inherit (fixeds.fetchgit."https://github.com/wheybags/glibc_version_header.git") url rev sha256;
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

  # easy-to-use stdenv adapter for all sorts of compatibility
  stdenvForceCompatibility = { reqs }: stdenv: let
    minDep = dep: version: deps: let
      curVersion = deps.${dep} or null;
      in if curVersion == null || builtins.compareVersions version curVersion < 0
        then deps // {
          "${dep}" = version;
        }
        else deps;
    minGlibc = minDep "glibc";
    f = req: {
      "ubuntu-12.04" = minGlibc "2.15";
      "ubuntu-14.04" = minGlibc "2.19";
      "ubuntu-16.04" = minGlibc "2.23";
      "ubuntu-18.04" = minGlibc "2.27";
    }.${req} or (abort "unknown compatibility requirement: ${req}");
    deps = pkgs.lib.foldr f {} reqs;
    glibcReq = deps.glibc or null;
    glibcAdapter = stdenvForceGlibcVersion {
      arch = if stdenv.hostPlatform.isx86_64 then "x64" else "x86";
      version = glibcReq;
    };
    adapters =
      pkgs.lib.optional (stdenv.hostPlatform.libc == "glibc" && stdenv.hostPlatform.isx86 && glibcReq != null) glibcAdapter;
  in pkgs.lib.pipe stdenv adapters;

  fetchGitLfs =
    { repoUrl
    , netrcVar ? "GIT_LFS_NETRC"
    , ref ? null
    }: pointer: let
    info = pkgs.lib.pipe pointer [
      builtins.readFile
      (pkgs.lib.splitString "\n")
      (map (builtins.match "([a-z0-9.-]+) (.+)"))
      (builtins.filter (re: re != null))
      (map (re: pkgs.lib.nameValuePair (builtins.elemAt re 0) (builtins.elemAt re 1)))
      pkgs.lib.listToAttrs
      (o: assert (o.version == "https://git-lfs.github.com/spec/v1"); o)
    ];
    oidParsed = builtins.match "([a-z0-9]+):(.+)" info.oid;
    oidHashAlgo = builtins.elemAt oidParsed 0;
    oidHash = builtins.elemAt oidParsed 1;
  in pkgs.stdenvNoCC.mkDerivation {
    name = pkgs.lib.strings.sanitizeDerivationName (baseNameOf pointer);

    outputHashMode = "flat";
    outputHashAlgo = oidHashAlgo;
    outputHash = oidHash;

    buildCommand = ''
      echo "''${${netrcVar}}" > .netrc
      echo -n '${pkgs.curl}/bin/curl -fLo $out ' > fetch.sh
      ${pkgs.curl}/bin/curl -fL --netrc-file .netrc \
        -H 'Content-Type: application/vnd.git-lfs+json' \
        -d ${pkgs.lib.escapeShellArg (builtins.toJSON ({
          operation = "download";
          transfers = ["basic"];
          objects = [{
            oid = oidHash;
            inherit (info) size;
          }];
        } // pkgs.lib.optionalAttrs (ref != null) {
          ref = {
            name = ref;
          };
        }))} \
        ${pkgs.lib.escapeShellArg repoUrl}/info/lfs/objects/batch \
        | ${pkgs.nodejs}/bin/node ${./git_lfs_fetcher.js} \
        >> fetch.sh
      . fetch.sh
    '';

    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

    impureEnvVars = pkgs.lib.fetchers.proxyImpureEnvVars ++ [
      netrcVar
    ];
  };
}
