#!/usr/bin/env bash

set -e

# ldap
WORKDIR=/opt/ldap
LDAPNAME=viya
OLCSUFFIX="dc=${LDAPNAME},dc=splab.pdsea.f5net.com"
LDAPDOMAINNAME=viya.splab.pdsea.f5net.com
LDAPHOST=$(hostname -f)
LDAPADMIN=ldapadm
OLCROOTDN="cn=${LDAPADMIN},${OLCSUFFIX}"
LDAPPASS="Junct10n"
SASUSERPASS="Junct10n"
SASDMINPASS="Junct10n"
sudo mkdir -p ${WORKDIR}
pushd ${WORKDIR}
sudo yum install net-tools ntp -y
sudo systemctl enable ntpd
sudo systemctl start ntpd
sudo yum install openldap compat-openldap openldap-clients \
               openldap-servers openldap-servers-sql \
               openldap-devel -y
sudo systemctl start slapd.service
sudo systemctl enable slapd.service
SLAPLDAPPASS=$(slappasswd -s ${LDAPPASS})

bash -c "cat << EOF | sudo tee db.ldif
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: ${OLCSUFFIX}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: ${OLCROOTDN}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW:  ${SLAPLDAPPASS}
EOF"

bash -c "cat << EOF | sudo tee monitor.ldif
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base=\"${OLCROOTDN}\" read by * none
EOF"

bash -c "cat << EOF | sudo tee base.ldif
dn: ${OLCSUFFIX}
dc: ${LDAPNAME}
objectClass: top
objectClass: domain

dn: ${OLCROOTDN}
objectClass: organizationalRole
cn: ${LDAPADMIN}
description: LDAP Manager

dn: ou=People,${OLCSUFFIX}
objectClass: organizationalUnit
ou: People

dn: ou=Group,${OLCSUFFIX}
objectClass: organizationalUnit
ou: Group
EOF"

THISUID=9990
for i in {1..8}; do
THISUSER=sasuser0${i}
THISGID=9999
bash -c "cat << EOF | sudo tee ${THISUSER}.ldif
dn: uid=${THISUSER},ou=People,${OLCSUFFIX}
objectClass: top
objectClass: posixAccount
objectClass: shadowAccount
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
sn: ${THISUSER}
cn: ${THISUSER}
uid: ${THISUSER}
homeDirectory: /home/${THISUSER}
loginShell: /bin/bash
gecos: ${THISUSER}
shadowLastChange: 17058
shadowMin: 0
shadowMax: 99999
shadowWarning: 7
userPassword: ${SLAPLDAPPASS}
gidNumber: ${THISGID}
uidNumber: ${THISUID}
EOF"
sudo mkdir /home/${THISUSER}
sudo chown ${THISUID}:${THISGID} /home/${THISUSER}
sudo chmod 700 /home/${THISUSER}
((THISUID+=1))
done


THISUSER=sasadmin
bash -c "cat << EOF | sudo tee ${THISUSER}.ldif
dn: uid=${THISUSER},ou=People,${OLCSUFFIX}
objectClass: top
objectClass: posixAccount
objectClass: shadowAccount
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
sn: ${THISUSER}
cn: ${THISUSER}
uid: ${THISUSER}
homeDirectory: /home/${THISUSER}
loginShell: /bin/bash
gecos: ${THISUSER}
shadowLastChange: 17058
shadowMin: 0
shadowMax: 99999
shadowWarning: 7
userPassword: ${SLAPLDAPPASS}
gidNumber: ${THISGID}
uidNumber: ${THISUID}
EOF"
sudo mkdir /home/${THISUSER}
sudo chown ${THISUID}:${THISGID} /home/${THISUSER}
sudo chmod 700 /home/${THISUSER}

bash -c "cat << EOF | sudo tee sasusers.ldif
dn: cn=sasusers,ou=Group,${OLCSUFFIX}
objectClass: extensibleObject
objectClass: top
objectClass: groupOfNames
cn: sasusers
member: uid=sasdemo,ou=People,${OLCSUFFIX}
displayName: SAS Users
gidNumber: 9999
memberUid: sasdemo
name: sasusers
EOF"

sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f db.ldif
sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f monitor.ldif
sudo cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
sudo chown -R ldap:ldap /var/lib/ldap
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
sudo ldapadd -x -w ${LDAPPASS} -D ${OLCROOTDN} -f base.ldif
sudo ldapadd -x -w ${LDAPPASS} -D ${OLCROOTDN} -f sasusers.ldif
for i in {1..8}; do
        THISUSER=sasuser0${i}
        ldapadd -x -w ${LDAPPASS} -D ${OLCROOTDN} -f ${THISUSER}.ldif
        ldappasswd -s ${SASUSERPASS} -w ${LDAPPASS} -D "${OLCROOTDN}" -x "uid=${THISUSER},ou=People,${OLCSUFFIX}"
done
THISUSER=sasadmin
ldapadd -x -w ${LDAPPASS} -D ${OLCROOTDN} -f ${THISUSER}.ldif
ldappasswd -s ${SASDMINPASS} -w ${LDAPPASS} -D "${OLCROOTDN}" -x "uid=${THISUSER},ou=People,${OLCSUFFIX}"


# ldap client
# ***run this section on every node***
sudo rm /etc/sssd/sssd.conf
LDAPNAME=viya
OLCSUFFIX="dc=${LDAPNAME},dc=splab.pdsea.f5net.com"
LDAPDOMAINNAME=viya.splab.pdsea.f5net.com
LDAPHOST=sas-viya-01.splab.pdsea.f5net.com
LDAPADMIN=ldapadm
OLCROOTDN="cn=${LDAPADMIN},${OLCSUFFIX}"
LDAPPASS="Junct10n"
SASUSERPASS="Junct10n"
SASDMINPASS="Junct10n"

sudo yum remove pam_ldap -y
sudo yum install sssd -y

bash -c "cat << EOF | sudo tee /etc/sssd/sssd.conf
[sssd]
config_file_version = 2
domains = ${LDAPDOMAINNAME}
services = nss, pam

[nss]

[pam]

[domain/${LDAPDOMAINNAME}]
# uncomment for high level of debugging
#debug_level = 9
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
access_provider = permit
ldap_uri = ldap://${LDAPHOST}:389/
ldap_default_bind_dn = ${OLCROOTDN}
ldap_default_authtok = ${LDAPPASS}
ldap_search_base = ${OLCSUFFIX}
ldap_user_fullname = displayName
ldap_group_object_class = groupOfNames
ldap_group_name = name
ldap_group_gid_number = gidNumber
ldap_group_member = memberUid
ldap_tls_reqcert = Allow
EOF"

sudo chmod 600 /etc/sssd/sssd.conf
sudo authconfig --enablesssd --enablesssdauth --enablemkhomedir --update
sudo systemctl start sssd
sudo systemctl enable sssd
