#####################################
# Making the workshop student image
#####################################

# The first thing you need is a Centos Cloud image
# I got the raw image from an Openstack deployment, but
# you can get it from:
#  http://cloud.centos.org/centos/7/images/
#
openstack image save --file ./centos7.raw "Centos 7"

# Add repos for the puppet modules and DLRN 
wget https://trunk.rdoproject.org/centos7/puppet-passed-ci/delorean.repo
wget https://trunk.rdoproject.org/centos7/delorean-deps.repo

mv centos7.raw student.raw

cat > prep.txt << EOF
upload delorean.repo:/etc/yum.repos.d/
upload delorean-deps.repo:/etc/yum.repos.d/
upload files/hsm_config.tar.gz:/root/
upload files/setup_student_vm.sh:/root/
upload files/0001-Make-cliff-output-match-the-actual-field-names.patch:/root
upload files/0002-Add-file-flag-for-secrets.patch:/root
upload files/flask.tar.gz:/root
install openstack-puppet-modules,git,389-ds-base,pki-ca,pki-kra,wget,unzip
install crudini,python-nss,expect,python-pip,python-devel,openssl,openssl-devel,openssl-libs,libffi,libffi-devel,python-virtualenv,gcc
run-command 'git clone https://github.com/openstack/puppet-openstack-integration.git /etc/puppet/modules/openstack_integration'
EOF
virt-customize -a student.raw -v --commands-from-file prep.txt

#
# Upload this image to your cloud to use.
#
openstack image create --disk-format raw --container-format bare  --file ./student.raw student_image_raw
