FROM quay.io/centos/centos:stream8
RUN dnf install -y rshim mstflint minicom pciutils
ADD scripts/ /usr/local/bin/
