#!/bin/bash
#
# Install guest additions and apply security updates.
#
# Usage:
#   install-guest-additions.sh input-box output-box
#

set -ex

box="$1"
outbox="$2"

name="$(basename "${outbox}" .box)-$$"

# Ensure vbguest plugin installed.
vagrant plugin list | grep vagrant-vbguest || vagrant plugin install vagrant-vbguest

# Create temporary vagrant directory.
export VAGRANT_CWD=$(mktemp -q -d "${name}.XXXXXX" || mktemp -q -d -t "${name}.XXXXXX")
if [ -z "${VAGRANT_CWD}" -o \! -d "${VAGRANT_CWD}" ]; then
	echo "Could not create a temporary directory for Vagrant"
	exit 1
fi

# Register base box.
vagrant box add --name "${name}" "${box}"

# Install security updates.
# Install compiler and kernel headers required for building guest additions.
cat >"${VAGRANT_CWD}/Vagrantfile" <<EOF
Vagrant.configure(2) do |config|
  config.vm.box = "${name}"
  config.ssh.insert_key = false

  # Do not attempt to install guest additions.
  config.vbguest.auto_update = false
  # Do not attempt to sync folder, dependent on guest additions.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  if Vagrant.has_plugin?("vagrant-cachier")
    # the VM has no VirtualBox guest additions yet, so vagrant-cachier
    # has to use rsync instead of native VBox shared folders.
    config.cache.synced_folder_opts = {
      type: :rsync
    }
  end
  config.vm.provision :shell,
    inline: "yum -y update --security && yum -y install gcc kernel-devel"
end
EOF
vagrant up --provider virtualbox
vagrant halt

# Reboot in case of kernel security updates above.
# Install guest additions.
# Verify guest additions via default /vagrant synced folder mount.
cat >"${VAGRANT_CWD}/Vagrantfile" <<EOF
Vagrant.configure(2) do |config|
  config.vm.box = "${name}"
  config.ssh.insert_key = false
  # Remove old kernels
  config.vm.provision :shell,
    inline: "yum -y install yum-utils && package-cleanup --y --oldkernels --count=1"
  # remove packages added for compiling VirtualBox guest additions, leave gcc
  config.vm.provision :shell,
    inline: "yum -y autoremove kernel-devel && yum clean all"
  # Clean yum cache, fill the partition with zeroes, and clean bash history
  config.vm.provision :shell,
    inline: ": > /root/.bash_history && history -c && dd if=/dev/zero of=/EMPTY bs=1M 2>&1 >/dev/null; rm -f /EMPTY && unset HISTFILE"
end
EOF
# bring up the machine so vagrant-vbguest can build and install VirtualBox guest additions
vagrant up --provider virtualbox
vagrant halt

# Export box.
vagrant package --output "${outbox}"

# Destroy VM.
vagrant destroy --force

# Unregister base box.
vagrant box remove "${name}"

# Clean up temporary vagrant directory.
rm -rf "${VAGRANT_CWD}"
