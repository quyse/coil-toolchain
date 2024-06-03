{ pkgsFun ? import <nixpkgs>
, pkgs ? pkgsFun {}
}:
rec {
  utils = import ./utils.nix {
    inherit pkgs;
  };

  refreshFixedsScript = pkgs.writeScript "refresh_fixeds" ''
    PATH=${pkgs.jq}/bin:${pkgs.nix}/bin:${pkgs.nix-prefetch-git}/bin:${pkgs.nodejs}/bin NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt node ${./refresh_fixeds.js}
  '';

  autoUpdateFixedsScript = fixedsFile: pkgs.writeScript "auto_update_fixeds" ''
    set -e
    cp --no-preserve=mode ${fixedsFile} ./fixeds.json
    ${refreshFixedsScript}
    if ! cmp -s ${fixedsFile} ./fixeds.json
    then
      echo 'update fixeds' > .git-commit
    fi
  '';

  touch = {
    stuffd = utils.stuffd {
      handlers = [];
    };

    inherit refreshFixedsScript;
  };

  path = ./.;
}
