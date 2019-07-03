#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright Clairvoyant 2017
#
# $Id$
#
# EXIT CODE:
#     0 = success
#     1 = print_help function (or incorrect commandline)
#     2 = ERROR: Must be root.
#
if [ -n "$DEBUG" ]; then set -x; fi
#
##### START CONFIG ###################################################

##### STOP CONFIG ####################################################
PATH=/usr/bin:/usr/sbin:/bin:/sbin

# Function to print the help screen.
print_help() {
  printf 'Usage:  %s --mountpoint <mountpoint>\n' "$1"
  printf '\n'
  printf '         -m|--mountpoint       Mountpoint of the unencrypted filesystem.\n'
  printf '         -g|--volumegroup      Volume group to create a logical volume with if using LVM for scratch space.\n'
  printf '         -s|--volumesize       Volume size in GiB to create the two needed logical volumes if using LVM.\n'
  printf '        [-h|--help]\n'
  printf '        [-v|--version]\n'
  printf '\n'
  printf '   ex.  %s --mountpoint /data/2\n' "$1"
  exit 1
}

# Function to check for root privileges.
check_root() {
  if [[ $(/usr/bin/id | awk -F= '{print $2}' | awk -F"(" '{print $1}' 2>/dev/null) -ne 0 ]]; then
    printf 'You must have root privileges to run this program.\n'
    exit 2
  fi
}

## If the variable DEBUG is set, then turn on tracing.
## http://www.research.att.com/lists/ast-users/2003/05/msg00009.html
#if [ $DEBUG ]; then
#  # This will turn on the ksh xtrace option for mainline code
#  set -x
#
#  # This will turn on the ksh xtrace option for all functions
#  typeset +f |
#  while read F junk
#  do
#    typeset -ft $F
#  done
#  unset F junk
#fi

# Process arguments.
while [[ $1 = -* ]]; do
  case $1 in
    -m|--mountpoint)
      shift
      MOUNTPOINT=$1
      ;;
    -g|--volumegroup)
      shift
      VOLUMEGROUP=$1
      ;;
    -s|--volumesize)
      shift
      VOLUMESIZE=$1
      ;;
    -h|--help)
      print_help "$(basename "$0")"
      ;;
    -v|--version)
      printf '\tMove data off the disks before encrypting with Navigator Encrypt.\n'
      exit 0
      ;;
    *)
      print_help "$(basename "$0")"
      ;;
  esac
  shift
done

echo "********************************************************************************"
echo "*** $(basename "$0")"
echo "********************************************************************************"
# Check to see if we have no parameters.
if [[ -z "$MOUNTPOINT" ]]; then print_help "$(basename "$0")"; fi

# Lets not bother continuing unless we have the privs to do something.
check_root

# main
umask 022
if [ ! -f /etc/navencrypt/keytrustee/clientname ]; then
  echo "** WARNING: This host is not yet registered.  Skipping..."
  exit 3
fi
if ! mountpoint -q "$MOUNTPOINT"; then
  echo "** ERROR: ${MOUNTPOINT} is not a mountpoint. Exiting..."
  exit 4
fi
if [ -d "${MOUNTPOINT}tmp" ]; then
  echo "** ERROR: ${MOUNTPOINT}tmp exists.  Is another move process running?  Exiting..."
  exit 5
fi

ESCMOUNTPOINT="${MOUNTPOINT//\//\\/}"
FULLDEVICE=$(mount | awk "\$3~/${ESCMOUNTPOINT}\$/{print \$1}")
ESCFULLDEVICE="${FULLDEVICE//\//\\/}"
# Find the parent device (ie not the partition).
# shellcheck disable=SC2001
DEVICE=$(echo "$FULLDEVICE" | sed -e 's|[0-9]$||')
if [ ! -b "$DEVICE" ]; then
  # shellcheck disable=SC2001
  DEVICE=$(echo "$DEVICE" | sed -e 's|.$||')
  if [ ! -b "$DEVICE" ]; then
    echo "** ERROR: ${DEVICE} does not exist. Exiting..."
    exit 6
  fi
fi
# Check to make sure we do not wipe a LVM.
if ! echo "$DEVICE" | grep -q ^/dev/sd ;then
  echo "** ERROR: ${DEVICE} is not an sd device. Exiting..."
  exit 7
fi

set -euo pipefail

CURRENTVOL=`basename ${MOUNTPOINT}`

# Creating backup LV for this data
if lvs | grep -q ${CURRENTVOL}backuplv
then
  echo "** ERROR: The ${CURRENTVOL}backuplv logical volume already exists."
  exit 1
else
  echo "** Creating the ${CURRENTVOL}backuplv logical volume..."
  lvcreate -Zy -Wy --yes -n ${CURRENTVOL}backuplv -L ${VOLUMESIZE}G ${VOLUMEGROUP}
  mkfs.xfs /dev/${VOLUMEGROUP}/${CURRENTVOL}backuplv
  mkdir ${MOUNTPOINT}backup
  echo "** Mounting ${CURRENTVOL}backuplv to ${MOUNTPOINT}backup..."
  mount -t xfs /dev/${VOLUMEGROUP}/${CURRENTVOL}backuplv ${MOUNTPOINT}backup
fi

# Creating temporary LV for this data
if lvs | grep -q ${CURRENTVOL}tmplv
then
  echo "** ERROR: The ${CURRENTVOL}tmplv logical volume already exists."
  exit 1
else
  echo "** Creating the ${CURRENTVOL}tmplv logical volume..."
  lvcreate -Zy -Wy --yes -n ${CURRENTVOL}tmplv -L ${VOLUMESIZE}G ${VOLUMEGROUP}
  mkfs.xfs /dev/${VOLUMEGROUP}/${CURRENTVOL}tmplv
  mkdir ${MOUNTPOINT}tmp
  echo "** Mounting ${CURRENTVOL}tmplv to ${MOUNTPOINT}tmp..."
  mount -t xfs /dev/${VOLUMEGROUP}/${CURRENTVOL}tmplv ${MOUNTPOINT}tmp
fi

echo "** Copying backup of ${MOUNTPOINT} to ${MOUNTPOINT}backup..."
cp -pr ${MOUNTPOINT}/* ${MOUNTPOINT}backup

echo "** Moving data off of ${MOUNTPOINT}..."
# shellcheck disable=SC2174
mv "${MOUNTPOINT}/"* "${MOUNTPOINT}tmp/"
umount "$MOUNTPOINT"
sed -e "/${ESCMOUNTPOINT} /d" -i /etc/fstab
chattr -i "$MOUNTPOINT"

echo "** Wiping the device to prepare it for navencrypt-prepare..."
dd if=/dev/zero of="$DEVICE" bs=1M count=10
kpartx -d "$DEVICE"
rm -f "$FULLDEVICE"

