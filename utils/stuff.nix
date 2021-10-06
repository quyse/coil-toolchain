{ pkgs
, lib
}:

rec {
  stuffd = { handlers }: pkgs.writeShellScriptBin "stuffd" ''
    CONFIG="$(${pkgs.coreutils}/bin/mktemp)"
    HOST="''${HOST:-127.0.0.1}" PORT="''${PORT:-8080}" ${pkgs.gettext}/bin/envsubst < ${pkgs.writeText "lighttpd.conf" ''
      server.bind = "''${HOST}"
      server.port = ''${PORT}
      server.stream-response-body = 1
      server.modules = ("mod_setenv", "mod_rewrite", "mod_cgi")
      server.document-root = "${stuffdCgiScript {
        inherit handlers;
      }}/bin"
      url.rewrite-once = ("^/" => "/stuffdCgiScript")
      cgi.assign = ("" => "")
      cgi.execute-x-only = "enable"
      setenv.add-environment = ("WORKDIR" => env.PWD)
    ''} > "$CONFIG"
    exec ${pkgs.lighttpd}/bin/lighttpd -Df "$CONFIG"
  '';

  stuffdCgiScript = { handlers }: let
    handlersDir = pkgs.symlinkJoin {
      name = "stuffd-handlers";
      paths = handlers;
    };
  in pkgs.writeShellScriptBin "stuffdCgiScript" ''
    set -eu
    cd "$WORKDIR"
    if [ "''${REQUEST_METHOD}" != "GET" ]
    then
      echo 'Content-Type: text/plain'
      echo 'Status: 405 Method Not Allowed'
      echo
      echo "stuffd: method ''${REQUEST_METHOD} not allowed"
      exit 0
    fi
    HANDLER=${handlersDir}/"''${HTTP_HOST}"
    if [ -x "$HANDLER" ]
    then
      "$HANDLER" "''${HTTP_X_STUFF_URL:-https://''${HTTP_HOST}''${REQUEST_URI}}"
    else
      echo 'Content-Type: text/plain'
      echo 'Status: 404 Not Found'
      echo
      echo "stuffd: unsupported host ''${HTTP_HOST}"
    fi
  '';

  fetchStuff = { name, url, hash ? null, sha256 ? null, sha1 ? null }: let
    hashObj = if hash != null then {
      outputHashAlgo = "null";
      outputHash = hash;
    } else if sha256 != null then {
      outputHashAlgo = "sha256";
      outputHash = sha256;
    } else if sha1 != null then {
      outputHashAlgo = "sha1";
      outputHash = sha1;
    } else throw "fetchStuff requires hash for: ${url}";
    parsedUrl = builtins.match "https?://([^/:]+)(:[0-9]+)?(/.*)" url;
    urlHost = builtins.elemAt parsedUrl 0;
  in pkgs.stdenvNoCC.mkDerivation (hashObj // {
    inherit name;
    nativeBuildInputs = [pkgs.curl];
    buildCommand = ''
      curl -fLo $out -H 'Host: '${lib.escapeShellArg urlHost} -H 'X-Stuff-Url: '${lib.escapeShellArg url} "''${STUFF_URL:?not set}"
    '';
    outputHashMode = "flat";
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "STUFF_URL"
    ];
  });
}
