{ pkgs
}:

rec {
  pnpm2nix = pkgs.callPackage "${pkgs.fetchFromGitHub {
    owner = "FliegendeWurst";
    repo = "pnpm2nix-nzbr";
    rev = "35f88a41d29839b3989f31871263451c8e092cb1";
    hash = "sha256-7Qzmy1snKbxFBKoqUrfyxxmEB8rPxDdV7PQwRiAR01o=";
  }}/derivation.nix" {
    nodejs = pkgs.nodejs.overrideAttrs (old: {
      passthru = (old.passthru or {}) // {
        pkgs = ((old.passthru or {}).pkgs or {}) // {
          pnpm = pkgs.pnpm_10;
        };
      };
    });
  };
}
