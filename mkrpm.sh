#!/bin/bash

# Build RPM for RHEL/CentOS
# eg. ./mkrpm_el.sh el7
dist=$1
[ -z "$dist" ] && echo "$0 {dist}" && exit 1

mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp L20.patch ~/rpmbuild/SOURCES/

spectool -g -R -f slurm-job-exporter-$dist.spec
rpmbuild --define "dist .$dist" -ba slurm-job-exporter-$dist.spec
