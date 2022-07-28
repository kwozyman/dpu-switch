SHELL := bash

CONTAINER_TAG=quay.io/kwozyman/toolbox:bluefield
REMOTE_DEBUG_SERVER=10.19.128.114
aicli=podman run --net host -it --rm -e AI_OFFLINETOKEN="$(shell cat ~/.kube/openshift_token.txt)" -v $(HOME)/.aicli:/root/.aicli:Z -v $(HOME)/.ssh:/root/.ssh:Z,ro -v $(PWD):/workdir -v $(HOME)/.aicli/openshift_pull_prod.json:/workdir/openshift_pull.json --workdir /workdir quay.io/karmab/aicli
CLUSTER_NAME='bf2testing'

default: cluster iso

install: install-systemd

install-mco:
	oc apply -f manifests/bf2-services.yml
install-systemd:
	yq '.spec.config.systemd.units[0].contents' manifests/bf2-services.yml > /etc/systemd/system/rshim.service
	yq '.spec.config.systemd.units[1].contents' manifests/bf2-services.yml > /etc/systemd/system/dpu-switch.service
	systemctl daemon-reload
install-remote-debug:
	yq '.spec.config.systemd.units[0].contents' manifests/bf2-services.yml | ssh root@$(REMOTE_DEBUG_SERVER) "cat > /etc/systemd/system/rshim.service"
	yq '.spec.config.systemd.units[0].contents' manifests/bf2-services.yml | ssh root@$(REMOTE_DEBUG_SERVER) "cat > /etc/systemd/system/dpu-switch.service"
	ssh root@$(REMOTE_DEBUG_SERVER) systemctl daemon-reload

cluster: FORCE
	echo "sno: true" > cluster.yaml
	echo "manifests: .rendered" >> cluster.yaml
	echo "base_dns_domain: redhat.com" >> cluster.yaml
	echo "additional_ntp_source: 0.north-america.pool.ntp.org" >> cluster.yaml
	echo -n "ignition_config_override: '" >> cluster.yaml
	cat cluster/disable-nic-template.yaml | yq '.metadata.labels["machineconfiguration.openshift.io/role"]="master" | .metadata.name="disable-nic-master"' | yq .spec.config.storage.files[0].contents.source=\"data:text/plain\;charset=utf-8\;base64,$(shell cat cluster/disabled-nics.conf | base64 -w0)\" -o json | jq '.spec.config' | jq -r '.ignition.config={}' | jq -cj  >> cluster.yaml && echo "'"  >> cluster.yaml
	cat cluster/static-network-aicli.yaml >> cluster.yaml
	mkdir -p .rendered
	cat cluster/disable-nic-template.yaml | yq '.metadata.labels["machineconfiguration.openshift.io/role"]="master" | .metadata.name="disable-nic-master"' | yq .spec.config.storage.files[0].contents.source=\"data:text/plain\;charset=utf-8\;base64,$(shell cat cluster/disabled-nics.conf | base64 -w0)\" > .rendered/disablenic-master.yaml
	$(aicli) create cluster $(CLUSTER_NAME) --paramfile cluster.yaml
iso:
	$(aicli) update infraenv -P image_type=minimal-iso $(CLUSTER_NAME)_infra-env
	$(aicli) download iso $(CLUSTER_NAME)_infra-env

build-container:
	podman build . --tag $(CONTAINER_TAG)
push-container:
	podman push $(CONTAINER_TAG)


clean: clean-cluster clean-files
clean-cluster:
	$(aicli) delete cluster $(CLUSTER_NAME)
clean-files:
	rm cluster.yaml
	rm -rf .rendered

FORCE: ;
