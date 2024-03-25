{ pkgs
, lib ? pkgs.lib
}:
rec {
  fetchGitLfs =
    { repoUrl
    , ref ? null
    , netrcVar ? "GIT_LFS_NETRC"
    }: pointer: let
    info = lib.pipe pointer [
      builtins.readFile
      (lib.splitString "\n")
      (map (builtins.match "([a-z0-9.-]+) (.+)"))
      (builtins.filter (re: re != null))
      (map (re: lib.nameValuePair (builtins.elemAt re 0) (builtins.elemAt re 1)))
      lib.listToAttrs
      (o: assert (o.version == "https://git-lfs.github.com/spec/v1"); o)
    ];
    oidParsed = builtins.match "([a-z0-9]+):(.+)" info.oid;
    outputHashAlgo = builtins.elemAt oidParsed 0;
    outputHash = builtins.elemAt oidParsed 1;
  in pkgs.callPackage ./utils/fetchgitlfs.nix {
    inherit pointer repoUrl ref netrcVar outputHashAlgo outputHash;
    inherit (info) size;
  };

  xml = import ./utils/xml.nix {
    inherit lib;
  };

  inherit (import ./utils/stuff.nix {
    inherit pkgs lib;
  }) stuffd fetchStuff;
}
