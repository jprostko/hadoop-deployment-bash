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
  printf '         -g|--volumegroup      Volume group as optionally specified earlier in navencrypt_evacuate.sh.\n'
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
    -h|--help)
      print_help "$(basename "$0")"
      ;;
    -v|--version)
      printf '\tPerform LVM-related cleanup after the navigator_move.sh script..\n'
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

CURRENTVOLUME=`basename ${MOUNTPOINT}`

set -euo pipefail
echo "** Performing cleanup of logical volumes and mount points..."
# shellcheck disable=SC2174
umount ${MOUNTPOINT}backup
umount ${MOUNTPOINT}tmp
rmdir ${MOUNTPOINT}backup
rmdir ${MOUNTPOINT}tmp
lvremove -f ${VOLUMEGROUP}/${CURRENTVOLUME}backuplv
lvremove -f ${VOLUMEGROUP}/${CURRENTVOLUME}tmplv

