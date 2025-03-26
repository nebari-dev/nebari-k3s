# HPC node names (with optional prefix)
HPC_MASTER01 = "hpc-master-01" + (ENV['HPC_VM_PREFIX'] || '')
HPC_MASTER02 = "hpc-master-02" + (ENV['HPC_VM_PREFIX'] || '')
HPC_MASTER03 = "hpc-master-03" + (ENV['HPC_VM_PREFIX'] || '')
# HPC_NODE01   = "hpc-node-01"   + (ENV['HPC_VM_PREFIX'] || '')
# HPC_NODE02   = "hpc-node-02"   + (ENV['HPC_VM_PREFIX'] || '')

Vagrant.configure("2") do |config|
  config.vm.box = "generic/rocky9"

  # ------------------------------------------------------------------
  # Master node 1 (primary)
  # ------------------------------------------------------------------
  config.vm.define HPC_MASTER01, primary: true do |master|
    master.vm.hostname = HPC_MASTER01

    # Private network for cluster traffic:
    master.vm.network "private_network", ip: "192.168.10.100"

    master.vm.provider "libvirt" do |libvirt|
      libvirt.memory = 16384
      libvirt.cpus   = 8
    end
  end

  # ------------------------------------------------------------------
  # Master node 2
  # ------------------------------------------------------------------
  config.vm.define HPC_MASTER02 do |master02|
    master02.vm.hostname = HPC_MASTER02
    master02.vm.network "private_network", ip: "192.168.10.101"

    master02.vm.provider "libvirt" do |libvirt|
      libvirt.memory = 4096
      libvirt.cpus   = 2
    end
  end

  # ------------------------------------------------------------------
  # Master node 3
  # ------------------------------------------------------------------
  config.vm.define HPC_MASTER03 do |master03|
    master03.vm.hostname = HPC_MASTER03
    master03.vm.network "private_network", ip: "192.168.10.102"

    master03.vm.provider "libvirt" do |libvirt|
      libvirt.memory = 4096
      libvirt.cpus   = 2
    end
  end

  # ------------------------------------------------------------------
  # Node 1
  # ------------------------------------------------------------------
  # config.vm.define HPC_NODE01 do |node01|
  #   node01.vm.hostname = HPC_NODE01
  #   node01.vm.network "private_network", ip: "192.168.10.201"

  #   node01.vm.provider "libvirt" do |libvirt|
  #     libvirt.memory = 2048
  #     libvirt.cpus   = 2
  #   end
  # end

  # # ------------------------------------------------------------------
  # # Node 2
  # # ------------------------------------------------------------------
  # config.vm.define HPC_NODE02 do |node02|
  #   node02.vm.hostname = HPC_NODE02
  #   node02.vm.network "private_network", ip: "192.168.10.202"

  #   node02.vm.provider "libvirt" do |libvirt|
  #     libvirt.memory = 2048
  #     libvirt.cpus   = 2
  #   end
  # end


  # ------------------------------------------------------------------
  # Ansible Provisioning (Optional)
  # ------------------------------------------------------------------
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "playbook.yaml"
    ansible.groups = {
      "master" => [ HPC_MASTER01, HPC_MASTER02, HPC_MASTER03 ],
      # "node"   => [ HPC_NODE01, HPC_NODE02 ],
      "k3s_cluster:children" => ["master"],
    }
    ansible.verbose = "v"
    ansible.raw_arguments = ["-f 5"]
  end


  # Public host bridge
  # config.vm.network "public_network", type: "bridge",
  #   dev: "br-dc8a0fa62369",
  #   mode: "bridge",
  #   network_name: "public-network",
  #   ip: "192.168.1.38"

end
