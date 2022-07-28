Helper scripts and Openshift manifests for Bluefield 2 switching from/to DPU/SmartNIC mode
===

# Prerequisits

* 64bit Red Hat / CentOS host with podman
* BF2 card physically installed and connected

# Backgroud

The [Nvidia Bluefield 2 DPUs](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/documents/datasheet-nvidia-bluefield-2-dpu.pdf) have two working modes: actual DPU or SmartNIC mode. In the later, the board acts as two regular ConnectX network interfaces. The goal of this demo is to prove if an Openshift cluster can be installed with BF2 in DPU mode, then switch to SmartNIC.

# Cluster installation

```
$ make cluster && make iso
```

this will create an Assisted Installer Openshift cluster using Red Hat's cloud service comprising of a Single Node Openshift using [aicli](https://github.com/karmab/aicli) and download a minimal .iso for installation on bare metal hosts. The assumptions made here are that the Openshift offline token exists in `~/.kube/openshift_token.txt` and that the Openshift pull-secret is located in `~/.aicli/openshift_pull_prod.json`. These can be tweaked beforehand by editing `Makefile` and changing the `aicli` variable to suit your needs. Same goes for the cluster name in the `CLUSTER_NAME` `Makefile` variable.

After the `.iso` file is downloaded, you can boot the host off of it and continue the installation in https://console.redhat.com/openshift/assisted-installer/clusters

In order to review the cluster parameters, you can review the `cluster.yaml` file created after `make cluster` and the directory `.rendered` which contains the ignition overrides. For example:

```
$ cat cluster.yaml
sno: true
manifests: .rendered
base_dns_domain: redhat.com
additional_ntp_source: 0.north-america.pool.ntp.org
ignition_config_override: '{"ignition":{"version":"3.1.0","config":{}},"storage":{"files":[{"contents":{"source":"data:text/plain;charset=utf-8;base64,W21haW5dCnJjLW1hbmFnZXI9ZmlsZQpbY29ubmVjdGlvbl0KaXB2Ni5kaGNwLWR1aWQ9bGwKaXB2Ni5kaGNwLWlhaWQ9bWFjCltrZXlmaWxlXQp1bm1hbmFnZWQtZGV2aWNlcz1pbnRlcmZhY2UtbmFtZTplbm8xLGludGVyZmFjZS1uYW1lOmVubzIsaW50ZXJmYWNlLW5hbWU6ZW5vMwo=","verification":{}},"filesystem":"root","mode":420,"path":"/etc/NetworkManager/conf.d/disablenic.conf"}]}}'
static_network_config:
- interfaces:
    - name: ens1f0
      type: ethernet
      state: up
      ethernet:
        auto-negotiation: true
        duplex: full
      ipv4:
        address:
        - ip: 15.15.15.2
          prefix-length: 24
        enabled: true
      mtu: 1500
      mac-address: 04:3f:72:ea:12:be
  dns-resolver:
    config:
      server:
      - 10.11.5.19
  routes:
    config:
    - destination: 0.0.0.0/0
      next-hop-address: 15.15.15.1
      next-hop-interface: ens1f0
```

In the example above, we make sure all other network interfaces are disabled and a static ip is set for the first DPU network interface.

# Drivers container

In order to interact with the Bluefield 2 card, we need [MSTFlint utility](https://github.com/Mellanox/mstflint), which is not available in the Openshift RHCOS image, therefore we need to build a container in order to run it:

```
$ make build-container && make push-container
```

The above builds the container image locally (using Podman) and then pushes it to a publicly available repo. By default, this is `quay.io/kwozyman/toolbox:bluefield` but it can be changed by editing the `Makefile` variable `CONTAINER_TAG`. Beware, also the `manifests/bf2-services.yaml` needs to be changed accordingly (see below).

# DPU Switch with Machine Config Operator

After the cluster is deployed and confirmed working, we want to setup two services on the host:

* rshim.service -- service for providing [rshim](https://github.com/Mellanox/rshim-user-space) on the host. If running correctly, it will expose `/dev/rshim0/*` on the host. This is useful for firmware upgrades, console access to the DPU and DPU reboot from the host.
* dpu-switch.service -- service for checking and actually switching the DPU in the desired mode

This can be done with `make install-mco` or simply by applying `manifest/bf2-service.yaml`. Of course, the assumption here is we have a working kubeconfig and `oc` tool.

The above simply created the two SystemD services and a configuration file in `/etc/default/bluefield` on the host. By using the variable `BF_MODE` in the configuration file, you can control the switch: if it's `nic`, it will switch to SmartNIC (ConnectX) mode, if it's `dpu` it will revert to DPU mode. Anything else simply queries the board and prints the current config to the journal.

**Important** How do the return codes work for the `dpu-switch` service/script?

Because the host needs a reboot after a mode switch, you will notice there is a `&& shutdown -r now` in the SystemD unit. This means the _success_ return code for the `scripts/bf-switch` script is in fact `120` if there is no mode change and `0` if there was a succesful mode change. Any other value will fail the unit and not trigger a reboot (see also `SuccessExitStatus=0 120` in the unit file).

# Bluefield 2 requirements

* a newer [firmware](https://network.nvidia.com/support/firmware/bluefield2/) for the card is required for enabling the SmartNIC mode: for this demo I've succesfully used version `24.33.1048`
* the DPU needs to be in [switchdev](https://www.kernel.org/doc/Documentation/networking/switchdev.txt) mode. A script is provided in `scripts/bf-switchdev` that needs to be run on the DPU to enable this mode.
