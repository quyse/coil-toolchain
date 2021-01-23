{ pkgs
, fixeds
}: let

windows = rec {
  qemu = pkgs.qemu_kvm;
  libguestfs = pkgs.libguestfs-with-appliance.override {
    inherit qemu; # no need to use full qemu
  };

  runPackerStep =
    { name ? "packer-disk"
    , disk ? null # set to the previous step, null for initial step
    , iso ? null
    , provisioners ? packerInitialProvisioners
    , extraMount ? null # path to mount (actually copy) into VM as drive D:
    , extraMountIn ? true # whether to copy data into VM
    , extraMountOut ? true # whether to copy data out of VM
    , extraMountSize ? "32G"
    , beforeScript ? ""
    , afterScript ? "mv build/packer-qemu $out"
    , outputHash ? null
    , outputHashAlgo ? "sha256"
    , outputHashMode ? "flat"
    , run ? true # set to false to return generated script instead of actually running it
    , headless ? true # set to false to run VM with UI for debugging
    }: let
    guestfishCmd = ''
      ${libguestfs}/bin/guestfish \
        disk-create extraMount.img qcow2 ${extraMountSize} : \
        add extraMount.img format:qcow2 label:extraMount : \
        run : \
        part-disk /dev/disk/guestfs/extraMount mbr : \
        part-set-mbr-id /dev/disk/guestfs/extraMount 1 07 : \
        mkfs ntfs /dev/disk/guestfs/extraMount1'';
    extraMountArg = pkgs.lib.escapeShellArg extraMount;
    script = ''
      echo 'Executing beforeScript...'
      ${beforeScript}
      ${pkgs.lib.optionalString (extraMount != null) (
        if extraMountIn then ''
          echo 'Copying extra mount data in...'
          tar -C ${extraMountArg} -c --dereference . | ${guestfishCmd} : \
            mount /dev/disk/guestfs/extraMount1 / : \
            tar-in - /
          rm -r ${extraMountArg}
        '' else ''
          echo 'Creating extra mount...'
          ${guestfishCmd}
        ''
      )}
      echo 'Starting VM...'
      PATH=${qemu}/bin:$PATH ${pkgs.buildPackages.packer}/bin/packer build --var cpus=$NIX_BUILD_CORES ${packerTemplateJson {
        name = "${name}.template.json";
        inherit disk iso provisioners headless;
        extraDisk = if extraMount != null then "extraMount.img" else null;
      }}
      ${pkgs.lib.optionalString (extraMount != null) ''
        ${pkgs.lib.optionalString extraMountOut ''
          echo 'Copying extra mount data out...'
          mkdir ${extraMountArg}
          ${libguestfs}/bin/guestfish \
            add extraMount.img format:qcow2 label:extraMount readonly:true : \
            run : \
            mount-ro /dev/disk/guestfs/extraMount1 / : \
            tar-out / - | tar -C ${extraMountArg} -xf -
        ''}
        echo 'Clearing extra mount...'
        rm extraMount.img
      ''}
      echo 'Executing afterScript...'
      ${afterScript}
    '';
    env = if outputHash != null then {
      inherit outputHash outputHashAlgo outputHashMode;
    } else {};
  in (if run then pkgs.runCommand name env else pkgs.writeScript "${name}.sh") script;

  initialDisk = { version ? "2019" }: runPackerStep {
    iso = windowsInstallIso {
      inherit version;
    };
  };

  packerTemplateJson =
    { name
    , cpus ? 1
    , memory ? 4096
    , disk ? null
    , iso ? null
    , output_directory ? "build"
    , provisioners
    , extraDisk ? null
    , headless ? true
    }: pkgs.writeText name (builtins.toJSON {
      builders = [(
        {
          type = "qemu";
          communicator = "winrm";
          cpus = "{{ user `cpus` }}";
          inherit memory headless output_directory;
          skip_compaction = true;
          # username and password are fixed in bento's autounattend
          winrm_username = "vagrant";
          winrm_password = "vagrant";
          winrm_timeout = "30m";
          shutdown_command = ''shutdown /s /t 10 /f /d p:4:1 /c "Packer Shutdown"'';
          shutdown_timeout = "15m";
          qemuargs = [
            # https://blog.wikichoon.com/2014/07/enabling-hyper-v-enlightenments-with-kvm.html
            [ "-cpu" "qemu64,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time" ]
            # main hdd
            [ "-drive" "file=${output_directory}/packer-qemu,if=virtio,cache=writeback,discard=ignore,format=qcow2,index=0" ]
          ] ++
          # cdroms
          pkgs.lib.optionals (disk == null && iso != null) [
            # main cdrom
            [ "-drive" "file=${iso.iso},media=cdrom,index=1" ]
            # virtio-win cdrom
            [ "-drive" "file=${virtio_win_iso},media=cdrom,index=2" ]
          ] ++
          # extra hdd
          pkgs.lib.optional (extraDisk != null) [ "-drive" "file=${extraDisk},if=virtio,cache=writeback,discard=ignore,format=qcow2,index=3" ];
        }
        // (if disk != null then {
          disk_image = true;
          use_backing_file = true;
          iso_url = disk;
          iso_checksum = "none";
          skip_resize_disk = true;
        } else if iso != null then {
          iso_url = iso.iso;
          iso_checksum = iso.checksum;
          floppy_files = [iso.autounattend];
        } else {})
      )];
      provisioners =
        pkgs.lib.optional (extraDisk != null) {
          type = "powershell";
          inline = [
            "Set-Disk -Number 1 -IsOffline $False"
            "Set-Disk -Number 1 -IsReadOnly $False"
          ];
        } ++
        provisioners;
      variables = {
        cpus = toString(cpus);
      };
    });

  # using bento as a maintained source of .iso URLs/checksums and autounattend scripts
  bento = pkgs.fetchgit {
    inherit (fixeds.fetchgit."https://github.com/chef/bento.git") url rev sha256;
  };

  windowsInstallIso = { version }: let
    templateDir = "packer_templates/windows";
    templateFile = "${bento}/${templateDir}/windows-${version}.json";
    autounattendFile = "${bento}/${templateDir}/answer_files/${version}/Autounattend.xml";
    # parse template file
    templateJson = builtins.fromJSON (builtins.readFile templateFile);
    # extract ISO url and download it ourselves
    iso = pkgs.fetchurl {
      url = templateJson.variables.iso_url;
      sha1 = checksum;
    };
    checksum = templateJson.variables.iso_checksum;
  in {
    inherit iso checksum;
    autounattend = autounattendFile;
  };

  packerInitialProvisioners =
    registryProvisioners initialRegistryFile ++
    [
      {
        type = "powershell";
        inline = [
          # uninstall defender
          "Uninstall-WindowsFeature -Name Windows-Defender -Remove"
          # power options
          "powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
          "powercfg /hibernate off"
          "powercfg /change -monitor-timeout-ac 0"
          "powercfg /change -monitor-timeout-dc 0"
        ];
      }
    ] ++
    [ { type = "windows-restart"; } ];

  # generate .reg file given a list of actions
  writeRegistryFile =
    { name ? "registry.reg"
    , keys
    }: let
    keyAction = keyName: keyValues: if keyValues == null then ''

      [-${keyName}]
    '' else ''

      [${keyName}]
      ${builtins.concatStringsSep "" (pkgs.lib.mapAttrsToList valueAction keyValues)}'';
    valueAction = valueName: valueValue: ''
      ${if valueName == "" then "@" else builtins.toJSON(valueName)}=${{
        int = "dword:${toString(valueValue)}";
        bool = "dword:${if valueValue then "1" else "0"}";
        string = builtins.toJSON(valueValue);
        null = "-";
      }.${builtins.typeOf valueValue}}
    '';
  in pkgs.writeText name ''
    Windows Registry Editor Version 5.00
    ${builtins.concatStringsSep "" (pkgs.lib.mapAttrsToList keyAction keys)}
  '';

  registryProvisioners = registryFile: let
    destPath = "C:\\Windows\\Temp\\${baseNameOf registryFile}";
  in [
    {
      type = "file";
      source = registryFile;
      destination = destPath;
    }
    {
      type = "windows-shell";
      inline = ["reg import ${destPath}"];
    }
  ];

  initialRegistryFile = writeRegistryFile {
    name = "initial.reg";
    keys = {
      # disable uac
      # https://docs.microsoft.com/en-us/windows/security/identity-protection/user-account-control/user-account-control-group-policy-and-registry-key-settings
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" = {
        EnableLUA = false;
        PromptOnSecureDesktop = false;
        ConsentPromptBehaviorAdmin = 0;
        EnableVirtualization = false;
        EnableInstallerDetection = false;
      };
      # disable restore
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\SystemRestore" = {
        DisableSR = true;
      };
      # disable windows update
      # https://docs.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU" = {
        NoAutoUpdate = true;
        AUOptions = 1;
      };
      # disable screensaver
      "HKEY_CURRENT_USER\\Control Panel\\Desktop" = {
        ScreenSaveActive = false;
      };
    };
  };

  virtio_win_iso = pkgs.fetchurl {
    inherit (fixeds.fetchurl."https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso") url sha256 name;
  };

  wine = (pkgs.winePackagesFor "wine64").minimal;

  initWinePrefix = ''
    mkdir .wineprefix
    export WINEPREFIX=$(readlink -f .wineprefix) WINEDEBUG=-all
    winecfg
  '';

  # convert list of unix-style paths to windows-style PATH var
  # paths must be pre-shell-escaped if needed
  makeWinePaths = paths: builtins.concatStringsSep ";" (map (path: "$(winepath -w ${path})") paths);
};
in windows
