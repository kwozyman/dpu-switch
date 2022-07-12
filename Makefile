SHELL := bash

CONTAINER_TAG=quay.io/kwozyman/toolbox:bluefield
REMOTE_DEBUG_SERVER=wsfd-advnetlab40.anl.lab.eng.bos.redhat.com

default: build-container install-mco

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

build-container:
	podman build . --tag $(CONTAINER_TAG)
	podman push $(CONTAINER_TAG)
