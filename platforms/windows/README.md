# Windows support

Allows to run commands in Windows VM as part of Nix-based build.

## Credits

This uses multiple third-party projects:

* [Packer](https://www.packer.io/) - the actual tool doing VM provisioning
* [QEMU](https://www.qemu.org/) - for VMs on Linux
* [chef/bento](https://github.com/chef/bento) - for maintained Windows .iso URLs/checksums and autounattend scripts
* [VirtIO-Win](https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/index.html) signed driver binaries by Fedora project

Inspiration and bits and pieces from:

* [WFVM](https://git.m-labs.hk/M-Labs/wfvm)
* [StefanScherer/packer-windows](https://github.com/StefanScherer/packer-windows)
* [mstorsjo/msvc-wine](https://github.com/mstorsjo/msvc-wine)
