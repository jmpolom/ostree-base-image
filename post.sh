#!/usr/bin/env bash

# Undo RPM scripts enabling units; we want the presets to be canonical
# https://github.com/projectatomic/rpm-ostree/issues/1803
set -xeuo pipefail
rm -rf /etc/systemd/system/*
systemctl preset-all
rm -rf /etc/systemd/user/*
systemctl --user --global preset-all

# Default to iptables-nft. Otherwise, legacy wins. We can drop this once/if we
# remove iptables-legacy. This is needed because alternatives don't work
# https://github.com/coreos/fedora-coreos-tracker/issues/677
# https://github.com/coreos/fedora-coreos-tracker/issues/676
set -xeuo pipefail
ln -sf /usr/sbin/ip6tables-nft         /etc/alternatives/ip6tables
ln -sf /usr/sbin/ip6tables-nft-restore /etc/alternatives/ip6tables-restore
ln -sf /usr/sbin/ip6tables-nft-save    /etc/alternatives/ip6tables-save
ln -sf /usr/sbin/iptables-nft          /etc/alternatives/iptables
ln -sf /usr/sbin/iptables-nft-restore  /etc/alternatives/iptables-restore
ln -sf /usr/sbin/iptables-nft-save     /etc/alternatives/iptables-save

# See: https://github.com/coreos/fedora-coreos-tracker/issues/1253
#      https://bugzilla.redhat.com/show_bug.cgi?id=2112857
#      https://github.com/coreos/rpm-ostree/issues/3918
# Temporary workaround to remove the SetGID binary from liblockfile that is
# pulled by the s390utils but not needed for /usr/sbin/zipl.
set -xeuo pipefail
rm -f /usr/bin/dotlockfile

# Set up default root config
mkdir -p /usr/lib/ostree
cat > /usr/lib/ostree/prepare-root.conf << EOF
[sysroot]
readonly = true
EOF

# bootupd
set -xeuo pipefail
# Until we have https://github.com/coreos/rpm-ostree/pull/2275
mkdir -p /run
# Transforms /usr/lib/ostree-boot into a bootupd-compatible update payload
/usr/bin/bootupctl backend generate-update-metadata /

# Taken from https://github.com/coreos/fedora-coreos-config/blob/aa4373201f415baff85701f7f96ab0583931af6c/overlay.d/05core/usr/lib/systemd/journald.conf.d/10-coreos-persistent.conf#L5
# Hardcode persistent journal by default. journald has this "auto" behaviour
# that only makes logs persistent if `/var/log/journal` exists, which it won't
# on first boot because `/var` isn't fully populated. We should be able to get
# rid of this once we move to sysusers and create the dir in the initrd.
mkdir -p /usr/lib/systemd/journald.conf.d/
cat > /usr/lib/systemd/journald.conf.d/10-centos-bootc-persistent.conf << 'EOF'
[Journal]
Storage=persistent
EOF

# Make kdump ignore `ignition.firstboot` when copying kargs from
# the running kernel to the kdump kernel when passing to be kexec.
# This makes it so kdump can be set up on the very first boot.
# Upstream request to have this upstream so we can stop carrying it here:
# https://lists.fedoraproject.org/archives/list/kexec@lists.fedoraproject.org/thread/5P4WIJLW2TSGF4PZGRZGOXYML4RXZU23/
sed -i -e 's/KDUMP_COMMANDLINE_REMOVE="/KDUMP_COMMANDLINE_REMOVE="ignition.firstboot /' /etc/sysconfig/kdump

# See https://github.com/containers/bootc/issues/358
# basically systemd-tmpfiles doesn't follow symlinks; ordinarily our
# tmpfiles.d unit for `/var/roothome` is fine, but this actually doesn't
# work if we want to use tmpfiles.d to write to `/root/.ssh` because
# tmpfiles gives up on that before getting to `/var/roothome`.
sed -ie 's, /root, /var/roothome,' /usr/lib/tmpfiles.d/provision.conf

# See also https://github.com/openshift/os/blob/f6cde963ee140c02364674db378b2bc4ac42675b/common.yaml#L156
# This one undoes the effect of
# # RHEL-only: Disable /tmp on tmpfs.
# Wants=tmp.mount
# in /usr/lib/systemd/system/basic.target
# We absolutely must have tmpfs-on-tmp for multiple reasons,
# but the biggest is that when we have composefs for / it's read-only,
# and for units with ProtectSystem=full systemd clones / but needs
# a writable place.
set -xeuo pipefail
mkdir -p /usr/lib/systemd/system/local-fs.target.wants
if [[ ! -f /usr/lib/systemd/system/local-fs.target.wants/tmp.mount ]]; then
  ln -sf ../tmp.mount /usr/lib/systemd/system/local-fs.target.wants
fi

# dracut
mkdir -p /usr/lib/dracut/dracut.conf.d
cat > /usr/lib/dracut/dracut.conf.d/20-basic.conf << 'EOF'
hostonly=no
dracutmodules+=" kernel-modules dracut-systemd systemd-initrd base ostree virtiosfs lvm crypt tpm2-tss "
EOF
