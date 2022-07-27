FROM quay.io/centos/centos:stream8
RUN dnf install -y rshim mstflint minicom pciutils iproute
ADD scripts/ /usr/local/bin/
