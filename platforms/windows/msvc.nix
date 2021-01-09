{ pkgs
, windows
}:

rec {
  # Nix-based package downloader for Visual Studio
  # inspiration: https://github.com/mstorsjo/msvc-wine/blob/master/vsdownload.py
  vsPackages = { versionMajor, versionPreview ? false, product ? "Microsoft.VisualStudio.Product.BuildTools" }: let

    channelUri = "https://aka.ms/vs/${toString versionMajor}/${if versionPreview then "pre" else "release"}/channel";

    channelManifest = builtins.fetchurl channelUri;
    channelManifestJSON = builtins.fromJSON (builtins.readFile channelManifest);

    manifestDesc = builtins.head (pkgs.lib.findSingle (c: c.type == "Manifest") null null channelManifestJSON.channelItems).payloads;
    # size, sha256 are actually wrong for manifest (facepalm)
    # manifest = pkgs.fetchurl {
    #   inherit (manifestDesc) url sha256;
    # };
    manifest = builtins.fetchurl manifestDesc.url;
    manifestJSON = builtins.fromJSON (builtins.readFile manifest);

    packages = pkgs.lib.groupBy (package: normalizeVsPackageId package.id) manifestJSON.packages;

    packageManifest = packageId: package:
      { arch
      , language
      , includeRecommended
      , includeOptional
      }: let
      packageVariantPred = packageVariant:
        (!(packageVariant ? chip) || packageVariant.chip == "neutral" || packageVariant.chip == arch) &&
        (!(packageVariant ? language) || packageVariant.language == "neutral" || packageVariant.language == language);
      packageVariants = builtins.filter packageVariantPred package;
      name = "${packageId}-${arch}-${language}${if includeRecommended then "-rec" else ""}${if includeOptional then "-opt" else ""}";
      packageVariantManifest = packageVariant: let
        payloadManifest = payload: pkgs.lib.nameValuePair
          (if packageVariant.type == "Vsix" then "payload.vsix" else payload.fileName)
          (pkgs.fetchurl {
            name = pkgs.lib.strings.sanitizeDerivationName payload.fileName;
            inherit (payload) url sha256;
          });
        depPred = depDesc:
          builtins.typeOf depDesc != "set" ||
          (!(depDesc ? type) ||
            (includeRecommended && depDesc.type == "Recommended") ||
            (includeOptional && depDesc.type == "Optional")) &&
          (!(depDesc ? when) || pkgs.lib.any (p: p == product) depDesc.when);
        depManifest = depPackageId: depDesc: packageManifests.${normalizeVsPackageId depPackageId} {
          arch = depDesc.chip or arch;
          inherit language;
          includeRecommended = false;
          includeOptional = false;
        };
      in rec {
        id = "${packageVariant.id},version=${packageVariant.version}" +
          (if packageVariant.chip or null != null then ",chip=${packageVariant.chip}" else "") +
          (if packageVariant.language or null != null then ",language=${packageVariant.language}" else "");
        # map of payloads, fileName -> fetchurl derivation
        payloads = builtins.listToAttrs (map payloadManifest (packageVariant.payloads or []));
        # list of dependencies (package manifests)
        dependencies = pkgs.lib.mapAttrsToList depManifest (pkgs.lib.filterAttrs (_dep: depPred) (packageVariant.dependencies or {}));
        layoutScript = let
          dir = id;
          sanitizeFileName = builtins.replaceStrings ["\\"] ["/"];
          directories = pkgs.lib.sort (a: b: a < b) (pkgs.lib.unique (
            pkgs.lib.mapAttrsToList (fileName: _payload:
              dirOf "${dir}/${sanitizeFileName fileName}"
            ) payloads
          ));
          directoriesStr = builtins.concatStringsSep " " (map (directory: pkgs.lib.escapeShellArg directory) directories);
        in ''
          ${if directoriesStr != "" then "mkdir -p ${directoriesStr}" else ""}
          ${builtins.concatStringsSep "" (pkgs.lib.mapAttrsToList (fileName: payload: ''
            ln -s ${payload} ${pkgs.lib.escapeShellArg "${dir}/${sanitizeFileName fileName}"}
          '') payloads)}
        '';
      };
    in rec {
      id = "${packageId}-${arch}-${language}";
      variants = map packageVariantManifest packageVariants;
      layoutScript = builtins.concatStringsSep "" (map (variant: variant.layoutScript) variants);
    };

    packageManifests = pkgs.lib.mapAttrs packageManifest packages;

    # resolve dependencies and return manifest for set of packages
    resolve = { packageIds, arch, language, includeRecommended ? false, includeOptional ? false }: let
      dfs = package: { visited, packages } @ args: if visited.${package.id} or false
        then args
        else let
          depPackages = pkgs.lib.concatMap (variant: variant.dependencies) package.variants;
          depsResult = pkgs.lib.foldr dfs {
            visited = visited // {
              "${package.id}" = true;
            };
            inherit packages;
          } depPackages;
        in {
          visited = depsResult.visited;
          packages = depsResult.packages ++ [package];
        };
      packages = (pkgs.lib.foldr dfs {
        visited = {};
        packages = [];
      } (map (packageId: packageManifests.${packageId} {
        inherit arch language includeRecommended includeOptional;
      }) (map normalizeVsPackageId (packageIds ++ [product])))).packages;
      vsSetupExe = {
        "Microsoft.VisualStudio.Product.BuildTools" = vsBuildToolsExe;
      }.${product};
      layoutJson = pkgs.writeText "layout.json" (builtins.toJSON {
        inherit channelUri;
        channelId = channelManifestJSON.info.manifestName;
        productId = product;
        installChannelUri = ".\\ChannelManifest.json";
        installCatalogUri = ".\\Catalog.json";
        add = map (packageId: "${packageId}${pkgs.lib.optionalString includeRecommended ";includeRecommended"}${pkgs.lib.optionalString includeOptional ";includeOptional"}") packageIds;
        addProductLang = [language];
      });
    in {
      layoutScript = ''
        ${builtins.concatStringsSep "" (map (package: package.layoutScript) packages)}
        ln -s ${channelManifest} ChannelManifest.json
        ln -s ${manifest} Catalog.json
        ln -s ${layoutJson} Layout.json
        ln -s ${layoutJson} Response.json
        ln -s ${vsSetupExe} vs_setup.exe
        ln -s ${vsInstallerExe} vs_installer.opc
      '';
    };

    # bootstrapper (vs_Setup.exe) - not sure what it is for
    # vsSetupExeDesc = builtins.head (pkgs.lib.findSingle (c: c.type == "Bootstrapper") null null channelManifestJSON.channelItems).payloads;
    # vsSetupExe = pkgs.fetchurl {
    #   inherit (vsSetupExeDesc) url sha256;
    # };

    vsBuildToolsExe = pkgs.fetchurl {
      url = "https://aka.ms/vs/${toString versionMajor}/${if versionPreview then "pre" else "release"}/vs_buildtools.exe";
      sha256 = "1w09ny2rczkiqg40hf9d54sffvgr4mh9cbslama32lzpyiar7yyc";
    };

    vsInstallerExe = pkgs.fetchurl {
      url = "https://aka.ms/vs/${toString versionMajor}/${if versionPreview then "pre" else "release"}/installer";
      sha256 = "08ra0m0yhmijgh2dd9a44b78q51y8aq5anxdwq167xd0ay7pgq6n";
    };

    disk = { packageIds, arch ? "x64", language ? "en-US", includeRecommended ? false, includeOptional ? false }: windows.runPackerStep {
      disk = windows.initialDisk;
      extraMount = "work";
      extraMountOut = false;
      beforeScript = ''
        mkdir -p work/vslayout
        cd work/vslayout
        ${(resolve {
          inherit packageIds arch language includeRecommended includeOptional;
        }).layoutScript}
        cd ../..
      '';
      provisioners = [
        {
          type = "windows-shell";
          inline = [
            ("D:\\vslayout\\vs_setup.exe --quiet --wait --noweb --norestart" +
              (builtins.concatStringsSep "" (map (packageId: " --add ${packageId}") packageIds)) +
              (pkgs.lib.optionalString includeRecommended " --includeRecommended") +
              (pkgs.lib.optionalString includeOptional " --includeOptional"))
          ];
        }
      ];
    };

  in {
    inherit packageManifests resolve disk;
  };

  normalizeVsPackageId = pkgs.lib.toLower;

  vs16BuildToolsDisk = (vsPackages { versionMajor = 16; }).disk;
  vs15BuildToolsDisk = (vsPackages { versionMajor = 15; }).disk;
}