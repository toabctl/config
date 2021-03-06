#!/bin/bash -ex

# Copyright 2014 Hewlett-Packard Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

ROOT=$(readlink -fn $(dirname $0)/..)
MODULE_PATH="${ROOT}/modules:/etc/puppet/modules"

export PUPPET_INTEGRATION_TEST=1

cat > clonemap.yaml <<EOF
clonemap:
  - name: '(.*?)/(.*)'
    dest: '/etc/puppet/modules/\2'
EOF

# Add puppet modules that should be installed to the end of this list
sudo -E /usr/zuul-env/bin/zuul-cloner -m clonemap.yaml --cache-dir /opt/git \
    git://git.openstack.org \
    openstack-infra/puppet-storyboard

if [[ ! -d applytest ]] ; then
    mkdir applytest
fi

csplit -sf applytest/puppetapplytest manifests/site.pp '/^$/' {*}
sed -i -e 's/^[^][:space:]$]/#&/g' applytest/puppetapplytest*
sed -i -e 's@hiera(.\([^.]*\).,\([^)]*\))@\2@' applytest/puppetapplytest*
mv applytest/*00 applytest/head  # These are the top-level variables defined in site.pp

if [[ `lsb_release -i -s` == 'CentOS' ]]; then
    if [[ `lsb_release -r -s` =~ '6' ]]; then
	CODENAME='centos6'
    fi
elif [[ `lsb_release -i -s` == 'Ubuntu' ]]; then
    CODENAME=`lsb_release -c -s`
fi

FOUND=0
for f in `find applytest -name 'puppetapplytest*' -print` ; do
    if grep -q "Node-OS: $CODENAME" $f; then
	cat applytest/head $f > $f.final
	FOUND=1
    fi
done

if [[ $FOUND == "0" ]]; then
    echo "No hosts found for node type $CODENAME"
    exit 1
fi

grep -v 127.0.1.1 /etc/hosts >/tmp/hosts
HOST=`echo $HOSTNAME |awk -F. '{ print $1 }'`
echo "127.0.1.1 $HOST.openstack.org $HOST" >> /tmp/hosts
sudo mv /tmp/hosts /etc/hosts

sudo mkdir -p /var/run/puppet
sudo -E bash -x ./install_modules.sh
echo "Running apply test on these hosts:"
find applytest -name 'puppetapplytest*.final' -print0
find applytest -name 'puppetapplytest*.final' -print0 | \
    xargs -0 -P $(nproc) -n 1 -I filearg \
        sudo puppet apply --modulepath=${MODULE_PATH} --noop --verbose --debug filearg > /dev/null
