# Build Nelua for Linux AArch64 on Fedora Incus

A Fedora x86-64 Incus host can run Fedora AArch64 user-space tools through
QEMU user-mode emulation. Use an x86-64 Incus guest with an AArch64 root
filesystem inside it. The GCC invoked in that filesystem emits AArch64 ELF
objects and executables.

## Prepare the guest

On the Fedora x86-64 Incus host, install Fedora's AArch64 QEMU user emulator
and check its binfmt registration. Run the Incus commands as an Incus
administrator.

```sh
sudo dnf install qemu-user-static-aarch64
cat /proc/sys/fs/binfmt_misc/qemu-aarch64
```

The registration must be enabled and include the `F` flag, so the kernel can
use the emulator across the chroot boundary. Use a fresh guest and image
alias for the following commands.

```sh
guest=nelua-arm-build
image=nelua-fedora-44-arm64
incus launch images:fedora/44/amd64 "$guest" \
  -c limits.cpu=4 -c limits.memory=4GiB -c security.nesting=true
incus image copy images:fedora/44/arm64 local: --alias "$image"
scratch=$(mktemp -d)
incus image export "$image" "$scratch/arm"
incus file push "$scratch/arm.root" "$guest/tmp/fedora-arm.squashfs"
rm "$scratch/arm" "$scratch/arm.root"
rmdir "$scratch"

incus exec "$guest" -- bash -s <<'GUEST'
set -eu
root=/srv/arm64
dnf -y install squashfs-tools </dev/null
unsquashfs -d "$root" /tmp/fedora-arm.squashfs
rm /tmp/fedora-arm.squashfs
for device in null zero random urandom; do
  touch "$root/dev/$device"
  mount --bind "/dev/$device" "$root/dev/$device"
done
cp -L --remove-destination /etc/resolv.conf "$root/etc/resolv.conf"
chroot "$root" uname -m
chroot "$root" dnf -y install gcc glibc-devel make git binutils xz </dev/null
chroot "$root" useradd -m builder
GUEST
```

Run the device-bind loop again after restarting the guest. The build uses the
guest's network and the host kernel. QEMU translates AArch64 user-space
instructions. Testing a kernel or UEFI application requires a separate
full-system firmware or boot test.

## Compile, run and package

Start an unprivileged shell inside the AArch64 filesystem.

```sh
incus exec "$guest" -- chroot --userspec=builder:builder /srv/arm64 \
  env HOME=/home/builder bash -c 'cd "$HOME" && exec bash'
```

Inside that shell, clone the public fork and build a compiler and an example.
`uname -m` should report `aarch64`, and both ELF headers should report
`AArch64`.

```sh
uname -m
git clone https://github.com/Spaceghost/nelua
cd nelua
make CC=gcc
readelf -h nelua-lua | grep 'Machine:'
./nelua --binary -o /tmp/nelua-hello examples/helloworld.nelua
readelf -h /tmp/nelua-hello | grep 'Machine:'
/tmp/nelua-hello
make package CC=gcc PKGNAME=nelua-linux-aarch64-fedora44
```

The archive at `pkg/nelua-linux-aarch64-fedora44.tar.xz` uses Fedora's glibc.
The [latest GitHub pre-release](https://github.com/Spaceghost/nelua/releases/tag/latest)
also ships a Linux AArch64 compiler package built with musl on native AArch64.
Nelua still uses a C toolchain to turn generated C into target binaries.

See the [Incus image guide](https://linuxcontainers.org/incus/docs/main/howto/images_manage/)
and the [Fedora QEMU package](https://packages.fedoraproject.org/pkgs/qemu/qemu-user-static-aarch64/)
for host setup.
