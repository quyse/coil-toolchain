{ pointer
, name ? lib.strings.sanitizeDerivationName (baseNameOf pointer)
, repoUrl
, ref
, size
, netrcVar
, outputHashMode ? "flat"
, outputHashAlgo
, outputHash
, stdenvNoCC
, curl
, nodejs
, cacert
, lib
}:
stdenvNoCC.mkDerivation {
  inherit name outputHashMode outputHashAlgo outputHash;

  nativeBuildInputs = [curl nodejs cacert];

  buildCommand = ''
    echo "''${${netrcVar}}" > .netrc
    echo -n 'curl -fLo $out ' > fetch.sh
    curl -fL --netrc-file .netrc \
      -H 'Content-Type: application/vnd.git-lfs+json' \
      -d ${lib.escapeShellArg (builtins.toJSON ({
        operation = "download";
        transfers = ["basic"];
        objects = [{
          oid = outputHash;
          inherit size;
        }];
      } // lib.optionalAttrs (ref != null) {
        ref = {
          name = ref;
        };
      }))} \
      ${lib.escapeShellArg repoUrl}/info/lfs/objects/batch \
      | node ${./git_lfs_fetcher.js} \
      >> fetch.sh
    . fetch.sh
  '';

  impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
    netrcVar
  ];
}
