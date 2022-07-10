SHELL := bash

CONTAINER_TAG=quay.io/kwozyman/toolbox:bluefield
REMOTE_DEBUG_SERVER=wsfd-advnetlab40.anl.lab.eng.bos.redhat.com

default: build-container

install: install-systemd

install-systemd:
	cp systemd/*.service /etc/systemd/system/
	systemctl daemon-reload
install-remote-debug:
	scp systemd/*.service root@$(REMOTE_DEBUG_SERVER):/etc/systemd/system/
	ssh root@$(REMOTE_DEBUG_SERVER) systemctl daemon-reload

build-container:
	podman build . --tag $(CONTAINER_TAG)
	podman push $(CONTAINER_TAG)
