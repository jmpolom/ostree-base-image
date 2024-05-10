#!/usr/bin/env bash

set -xeuo pipefail

# Install filesystem type (mandatory)
mkdir -p /usr/lib/bootc/install
cat > /usr/lib/bootc/install/00-fedora-ostree-base.toml << EOF
[install.filesystem.root]
type = "btrfs"
EOF

# Set up default root config
mkdir -p /usr/lib/ostree
cat > /usr/lib/ostree/prepare-root.conf << EOF
[sysroot]
readonly = true
EOF

# Undo RPM scripts enabling units; this uses defined service presets.
# This could and should be removed if systemd-firstboot use is desired.
rm -rf /etc/systemd/system/*
systemctl preset-all
rm -rf /etc/systemd/user/*
systemctl --user --global preset-all

# bootupd
# Until we have https://github.com/coreos/rpm-ostree/pull/2275
mkdir -p /run
# Transforms /usr/lib/ostree-boot into a bootupd-compatible update payload
/usr/bin/bootupctl backend generate-update-metadata

# Persistent journal by default. journald "auto" behaviour only makes logs
# persistent if `/var/log/journal` exists, which it doesn't on first boot
# because `/var` isn't fully populated. We should be able to get rid of this
# once we move to sysusers and create the dir in the initrd.
mkdir -p /usr/lib/systemd/journald.conf.d/
cat > /usr/lib/systemd/journald.conf.d/10-bootc-persistent.conf << 'EOF'
[Journal]
Storage=persistent
EOF

# See https://github.com/containers/bootc/issues/358
# basically systemd-tmpfiles doesn't follow symlinks; ordinarily our
# tmpfiles.d unit for `/var/roothome` is fine, but this actually doesn't
# work if we want to use tmpfiles.d to write to `/root/.ssh` because
# tmpfiles gives up on that before getting to `/var/roothome`.
sed -ie 's, /root, /var/roothome,' /usr/lib/tmpfiles.d/provision.conf
# Because /var/roothome is also defined in rpm-ostree-0-integration.conf
# we need to delete /var/roothome
sed -ie '/^d- \/var\/roothome /d' /usr/lib/tmpfiles.d/provision.conf

# hack to get rootfiles for bash
cat > /usr/lib/tmpfiles.d/rootfiles-bash.conf << 'EOF'
C!  /var/roothome/.bashrc           -       -       -       -       /usr/etc/skel/.bashrc
C!  /var/roothome/.bash_profile     -       -       -       -       /usr/etc/skel/.bash_profile
C!  /var/roothome/.bash_logout      -       -       -       -       /usr/etc/skel/.bash_logout
EOF

# dracut
mkdir -p /usr/lib/dracut/dracut.conf.d
cat > /usr/lib/dracut/dracut.conf.d/20-basic.conf << 'EOF'
hostonly=no
add_dracutmodules+=" kernel-modules dracut-systemd systemd-initrd base ostree virtiofs lvm crypt tpm2-tss "
EOF

# keep it lean, default to no recommends with dnf
mkdir -p /etc/dnf
cat > /etc/dnf/dnf.conf << 'EOF'
[main]
install_weak_deps=False
EOF
