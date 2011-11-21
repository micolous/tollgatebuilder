#!/bin/sh

INSTALL_DIR="/mnt/pub6/Dump/tollgatebuilder/target/"

WAN_IF="eth0"

LAN_IF="eth1"
LAN_IP="10.4.0.1"
LAN_NM="24"
LAN_NET="10.4.0.0"

LAN_DHCP_START="10.4.0.40"
LAN_DHCP_END="10.4.0.254"

LAN_HN="portal.example.tollgate.org.au"

DEBIAN_MIRROR="http://localhost/pub/debian/"
SECURITY_MIRROR="http://localhost/pub/debian-security/"
DEBIAN_VER="squeeze"

# will install linux-image-${KERNEL_ARCH}.
# to find which values are appropriate, see
# http://packages.debian.org/search?keywords=linux-image-&searchon=names&suite=stable&section=all
KERNEL_ARCH="686"

