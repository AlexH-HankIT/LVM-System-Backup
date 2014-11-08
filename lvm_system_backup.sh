#!/bin/bash
#
# Author: MrCrankHank
#

# Define default vars
hostname=$(</etc/hostname)

if [ -f /etc/default/lvm_system_backup ]; then
        . /etc/default/lvm_system_backup
else
	if [ -z $1 ]; then
		echo "Can't find config file at default location"
		echo "Please specify one as first parameter"
		exit 1
	fi

	if [ -f $1 ]; then
		true
	else
		echo "Can't find config file at $1"
		echo "Please check the path and come back"
		exit 1
	fi
fi

if [ -z $BACKUP_BOOT ]; then
	echo "BACKUP_BOOT is not configured!"
	echo "Please check the config file!"
	exit 1
fi

if [ $BACKUP_BOOT == 1 ]; then
	if [[ -z "$VG_NAME" && -z "$DIR" && -z "$HOST" && -z "$USER" && -z "$DISK" && -z "$BOOT" ]]; then
		echo "Important vars are missing!"
		echo "Please check the config file!"
		exit 1
	fi
else
	if [[ -z "$VG_NAME" && -z "$DIR" && -z "$HOST" && -z "$USER" ]]; then
		echo "Important vars are missing!"
		echo "Please check the config file!"
		exit 1
	fi
fi

if [ -d /dev/$VG_NAME ]; then
	true
else
	echo "VG $VG_NAME not found!"
	exit 1
fi

# Create dir var with subfolders
datum=`date +%d.%m.%y`
time=`date +"%T"`
DIR=$DIR/$hostname/$datum

# Create list with logical volumes
lvdisplay $VG_NAME | grep -e "LV Name" | tr -d ' ' | sed -e 's/LVName//g' > /tmp/lvs

# Exit trap to delete the snapshots, if the script terminates to early
function finish {
        while read lv; do
                if [ -e /dev/$VG_NAME/${lv}_snap ]; then
                        lvremove -f /dev/$VG_NAME/${lv}_snap
                fi
        done < /tmp/lvs
}
trap finish EXIT

function backup_layout {
	sfdisk -d $DISK > /tmp/part_table
	scp /tmp/part_table ${USER}@$HOST:$DIR/part_table
	rm /tmp/part_table

	vgcfgbackup -f /tmp/lvm_structure /dev/$VG_NAME
	scp /tmp/lvm_structure ${USER}@$HOST:$DIR/lvm_structure
	rm /tmp/lvm_structure
}

function backup_lvs {
	while read lv; do
		lvcreate --snapshot -L 3G -n ${lv}_snap /dev/$VG_NAME/$lv
		dd if=/dev/$VG_NAME/${lv}_snap | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/${lv}.img.gz
		lvremove -f /dev/$VG_NAME/${lv}_snap
	done < /tmp/lvs
}

# Create remote backup dir
ssh ${USER}@$HOST mkdir -p $DIR

# Backup lvm and mbr layout
backup_layout

if [ $BACKUP_BOOT == 1 ]; then
	# Create image of /boot
	dd if=$BOOT | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/boot.img.gz

	# Create image of mbr with grub
	dd if=$DISK bs=446 count=1 | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/mbr.img.gz
fi

# Backup the logical volumes
backup_lvs
