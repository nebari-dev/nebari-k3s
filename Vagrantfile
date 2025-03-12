# Names (appended with an optional prefix)
HPC_MASTER01 = "hpc-master-01" + (ENV['HPC_VM_PREFIX'] || '')
HPC_NODE01   = "hpc-node-01"   + (ENV['HPC_VM_PREFIX'] || '')
HPC_NODE02   = "hpc-node-02"   + (ENV['HPC_VM_PREFIX'] || '')

Vagrant.configure("2") do |config|
  config.vm.box = "generic/rocky9"

  # ------------------------------------------------------------------
  # Master node (active)
  #   Mirrors `[master]` in hosts.ini with IP 192.168.10.100
  # ------------------------------------------------------------------
  config.vm.define HPC_MASTER01, primary: true do |master|
    master.vm.hostname = HPC_MASTER01
    master.vm.network "private_network", ip: "192.168.10.100"

    master.vm.provider "libvirt" do |libvirt|
      libvirt.memory = 4096
      libvirt.cpus   = 8
    end
  end

  # ------------------------------------------------------------------
  # Node 1 (commented, matches the idea of commented IP in hosts.ini)
  #   Mirrors `[node]` in hosts.ini with IP 192.168.10.101
  # ------------------------------------------------------------------
  config.vm.define HPC_NODE01 do |node01|
    node01.vm.hostname = HPC_NODE01
    node01.vm.network "private_network", ip: "192.168.10.101"

    node01.vm.provider "libvirt" do |libvirt|
      libvirt.memory = 2048
      libvirt.cpus   = 2
    end
  end

  # ------------------------------------------------------------------
  # Node 2 (commented, matches the idea of commented IP in hosts.ini)
  #   Mirrors `[node]` in hosts.ini with IP 192.168.10.102
  # ------------------------------------------------------------------
  config.vm.define HPC_NODE02 do |node02|
    node02.vm.hostname = HPC_NODE02
    node02.vm.network "private_network", ip: "192.168.10.102"

    node02.vm.provider "libvirt" do |libvirt|
      libvirt.memory = 2048
      libvirt.cpus   = 2
    end
  end

  # ------------------------------------------------------------------
  # Optional Ansible Provisioning
  # ------------------------------------------------------------------
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "playbook.yaml"

    # Match groups from hosts.ini:
    ansible.groups = {
      "master" => [ HPC_MASTER01 ],
      "node" => [ HPC_NODE01, HPC_NODE02 ],
      "k3s_cluster:children" => ["master", "node"]
    }

    ansible.verbose = "v"       # or "vv", etc.
    ansible.raw_arguments = [
      "-f 5",  # up to 5 hosts in parallel
    ]
  end
end
