# Coil Toolchain

Nix-based toolchains for game development.

## Features

* Clang toolchain with statically-linked libc++
  * native for Linux
  * cross-compiling MinGW-based for Windows
* Stdenv adapters for forcing GLIBC compatibility with various Linux versions
* A set of libraries adapted for the toolchain and static linking
* Utils for creating and running Windows VMs
* [refresh_fixeds.js](refresh_fixeds.js) script for maintaining [fixeds.json](fixeds.json) file
