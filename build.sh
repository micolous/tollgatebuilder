#!/bin/sh
# build.sh
# Builds Debian environment for tollgate.
#
# Install the following first!
#   apt-get install debootstrap
# 

if [ "$(whoami)" != "root" ]; then
	echo "This script needs to be run as root."
	exit 1
fi

# make sure debootstrap is installed
apt-get install -y debootstrap

# load parameter file
. ./parameters.sh

if [ "/" = "$INSTALL_DIR" ] ; then
  echo "Cowardly refusing to install to / as it would break your system."
  exit 1
fi

echo "# TOLLGATE BUILDER PARAMETERS #"
echo ""
echo "Hostname . . . . . : $LAN_HN"
echo "WAN Interface. . . : $WAN_IF (dhcp)"
echo "LAN Interface. . . : $LAN_IF"
echo "  IP Address . . . : $LAN_IP"
echo "  Network. . . . . : $LAN_NET/$LAN_NM"
echo "  DHCP Range . . . : $LAN_DHCP_START - $LAN_DHCP_END"
echo "Installation Dir . : $INSTALL_DIR"
echo "Debian mirror. . . : $DEBIAN_MIRROR"
echo "Security mirror. . : $SECURITY_MIRROR"
echo "Debian version . . : $DEBIAN_VER"
echo "Kernel image . . . : linux-image-${KERNEL_ARCH}"
echo ""
echo "Beware: this will consume about 2GB of disk space, and download"
echo "approximately 400MB from the specified mirror.  It is advisable to use"
echo "a local Debian mirror."
echo ""
echo "Press RETURN to continue, or ^C to cancel..."
read Y

# calculate the reverse domain

if [ $LAN_NM -gt 30 ]; then
	echo "Netmask greater than 30"
	exit 1
elif [ $LAN_NM -gt 23 ]; then
	REVERSE_DNS="`echo $LAN_NM | cut -d. -f3,2,1`.in-addr.arpa"
elif [ $LAN_NM -gt 15 ]; then
	REVERSE_DNS="`echo $LAN_NM | cut -d. -f2,1`.in-addr.arpa"
elif [ $LAN_NM -gt 7 ]; then
	REVERSE_DNS="`echo $LAN_NM | cut -d. -f1`.in-addr.arpa"
else
	echo "Netmask less than 8"
	exit 1
fi

DOMAIN="`echo $LAN_HN | cut -d. -f2-`"
LOCAL_NAME="`echo $LAN_HN | cut -d. -f1`"

echo ""
echo "Beginning installation!"

debootstrap --include=screen,nmap,python-dbus,gitweb,openssh-server,openssh-client,joe,openssl,locales,python-iplib,python-lxml,python-pip,git,dnsmasq,iptables,module-assistant,xtables-addons-source,xtables-addons-common,build-essential,apache2,libapache2-mod-wsgi "${DEBIAN_VER}" "${INSTALL_DIR}" "${DEBIAN_MIRROR}"

echo "Configuring..."

cat >> "${INSTALL_DIR}/etc/network/interfaces" << EOF
auto ${WAN_IF}
iface ${WAN_IF} inet dhcp

auto ${LAN_IF}
iface ${LAN_IF} inet static
  address ${LAN_IP}
  netmask ${LAN_NM}
EOF

cat >> "${INSTALL_DIR}/etc/apt/souces.list" << EOF
deb-src ${DEBIAN_MIRROR} ${DEBIAN_VER} main

# security mirror
deb ${SECURITY_MIRROR} ${DEBIAN_VER}/updates main
deb-src ${SECURITY_MIRROR} ${DEBIAN_VER}/updates main
EOF

cat >> "${INSTALL_DIR}/etc/dnsmasq.d/tollgate.conf" << EOF
interface=${LAN_IF}
expand-hosts
domain=${DOMAIN},${LAN_IF}/${LAN_NM}
dhcp-range=${LAN_DHCP_START},${LAN_DHCP_END},7d

# lets tell windows not to be silly
dhcp-option=19,0 # disable ip-forwarding
dhcp-option=46,8 # netbios node type
dhcp-option=vendor:MSFT,2,1i # tell windows to release the lease when shutting down

# helpfully Windows ICS sets this as well.
dhcp-authoritative
EOF

cat >> "${INSTALL_DIR}/etc/hosts" << EOF
${LAN_IP} ${LAN_HN} ${LOCAL_NAME}
EOF

echo $LOCAL_NAME > ${INSTALL_DIR}/etc/hostname

echo "Updating package sources..."
chroot "${INSTALL_DIR}" /usr/bin/apt-get update

echo "Setting locale in environment from host system and generating locales..."
cp /etc/locale.gen "${INSTALL_DIR}/etc/locale.gen"
chroot "${INSTALL_DIR}" /usr/sbin/locale-gen

echo "Installing a kernel and some more packages..."
chroot "${INSTALL_DIR}" /usr/bin/apt-get install -y "linux-image-2.6-${KERNEL_ARCH}" "linux-headers-2.6-${KERNEL_ARCH}"

# in wheezy, this now has xtables-addons-dkms.
# but we're on squeeze :'(
echo "Building kernel modules..."
chroot "${INSTALL_DIR}" /usr/bin/module-assistant -n -k "`echo ${INSTALL_DIR}/usr/src/linux-headers-*-${KERNEL_ARCH} | cut -b$[${#INSTALL_DIR}+1]-`" a-i xtables-addons

echo "Installing tollgate dependancy python modules..."
chroot "${INSTALL_DIR}" /usr/bin/pip install django pip

echo "Grabbing tollgate MASTER...."
chroot "${INSTALL_DIR}" /usr/bin/git clone git://github.com/micolous/tollgate.git /opt/tollgate

echo "Populating the tollgate database..."
chroot "${INSTALL_DIR}" /usr/bin/make -C /opt/tollgate
chroot "${INSTALL_DIR}" /opt/tollgate/manage.py syncdb
chroot "${INSTALL_DIR}" /opt/tollgate/manage.py migrate
chroot "${INSTALL_DIR}" /opt/tollgate/scraper.py


echo "Configurating apache2..."
chroot "${INSTALL_DIR}" /usr/sbin/a2enmod wsgi
chroot "${INSTALL_DIR}" /usr/sbin/a2enmod ssl
chroot "${INSTALL_DIR}" /usr/sbin/a2ensite default
chroot "${INSTALL_DIR}" /usr/sbin/a2dissite default-ssl
# the example configuration is pretty much fine, let's steal that.
sed "s/portal.example.tollgate.org.au/${LAN_HN}/g" < ${INSTALL_DIR}/opt/tollgate/example/apache2/tollgate-vhost > ${INSTALL_DIR}/etc/apache2/sites-available/default

echo "Generating certificates..."
chroot "${INSTALL_DIR}" /bin/sh << EOF
#!/bin/sh
mkdir -p /etc/apache2/ssl
chmod 700 /etc/apache2/ssl
cd /etc/apache2/ssl
openssl req -new -out tollgate-cert.csr -passout pass:password -subj "/C=AU/ST=FAKE/L=Example/O=tollgate example certificate/OU=captive portal/CN=${LAN_HN}"
openssl rsa -passin pass:password -in privkey.pem -out tollgate-priv.key
openssl x509 -in tollgate-cert.csr -out tollgate-cert.pem -req -signkey tollgate-priv.key -days 3650
EOF

