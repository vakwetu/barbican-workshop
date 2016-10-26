########
# setup
########
sed -i'' "s/localhost /`hostname` localhost /" /etc/hosts

############################################################
#  Install and configure Openstack services through puppet
############################################################

cat > scenario.pp << EOF
include ::openstack_integration
class { '::openstack_integration::config':
  ssl  => true,
  ipv6 => false,
}
include ::openstack_integration::cacert
include ::openstack_integration::memcached
include ::openstack_integration::rabbitmq
include ::openstack_integration::mysql
include ::openstack_integration::keystone
include ::openstack_integration::barbican
EOF

puppet apply --modulepath /etc/puppet/modules:/usr/share/puppet/modules:/usr/share/openstack-puppet/modules scenario.pp


####################################################
# configure directory server for Dogtag internal DB
####################################################

cd ~
cat > ~/389.inf << EOF
[General]    
FullMachineName=`hostname`    
SuiteSpotUserID=nobody    
ServerRoot=/var/lib/dirsrv    
[slapd]    
ServerPort=389    
ServerIdentifier=dogtag-389    
Suffix=dc=example,dc=com    
RootDN=cn=Directory Manager    
RootDNPwd=redhat123    
EOF

setup-ds.pl --silent -f ~/389.inf

##############################
# configure dogtag CA and KRA
##############################

cat > ~/spawn.cfg << EOF
[DEFAULT]
pki_instance_name=pki-tomcat
pki_https_port=18443
pki_http_port=18080

pki_admin_password=redhat123
pki_security_domain_password=redhat123
pki_security_domain_https_port=18443
pki_client_pkcs12_password=redhat123
pki_client_database_password=redhat123
pki_ds_password=redhat123

[Tomcat]
pki_ajp_port=18009
pki_tomcat_server_port=18005

[KRA]
pki_issuing_ca_https_port=18443
EOF

pkispawn -s CA -f spawn.cfg
sleep 20
pkispawn -s KRA -f spawn.cfg

################################
# Set up barbican to use dogtag
################################

# create admin cert PEM file
cat > create_admin_cert_pem << EOF
#!/usr/bin/expect -f

set timeout -1
spawn openssl pkcs12 -in /root/.dogtag/pki-tomcat/ca_admin_cert.p12 -out /etc/barbican/kra_admin_cert.pem -nodes
match_max 100000
expect -exact "Enter Import Password:"
send -- "redhat123\r"
expect eof
EOF

expect create_admin_cert_pem
chown barbican: /etc/barbican/kra_admin_cert.pem

# create nssdb and store transport cert
mkdir -p /etc/barbican/alias
echo "password123" > pwfile
certutil -N -d /etc/barbican/alias -f pwfile
rm pwfile
chown -R barbican: /etc/barbican/alias

pki  -p 18080 -h localhost cert-show 0x7 --output transport.pem
certutil -d /etc/barbican/alias/ -A -n "KRA transport cert" -t "u,u,u" -i transport.pem

# modify barbican config and restart barbican
crudini --set /etc/barbican/barbican.conf secretstore enabled_secretstore_plugins dogtag_crypto
crudini --set /etc/barbican/barbican.conf dogtag_plugin dogtag_port 18443
systemctl restart httpd.service
 

