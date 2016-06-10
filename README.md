# clfs-arm64

This script aimed to build a clfs based on aarch64. It integrates download/build/run a system on linux.

# prerequisite packages:

- fedora:
    dnf install flex libfdt-devel bison texinfo libtool gcc-g++
    (To find a missing package name: dnf whatprovides */<program>)
- ubuntu:
    apt-get install libglib2.0-dev libpixman-1-dev libfdt-dev zlib1g-dev texinfo bison flex
