#!/bin/bash
# Modular bootstrap script
# The real work happens in functions, the main function is at the end

# Random string generator
# Input: length of randomly generated string
randstring () {

	echo $(cat /dev/random | tr -cd "[:alnum:]" | head -c $1)
}

# Random key generator
# Input: full path to key name
randkey () {
	dd if=/dev/random of=$1 bs=1024 count=1000
	chmod 0400 $1
	logger "$0: random key generated $1"
	echo $1
}

# Wipe random key with zero's and delete
# Input: full path to key name
wipekey () {
	# We are done with the encryption key, lets throw it away
    # Overwrite it with zeros
        dd if=/dev/zero of=$1 bs=1024 count=1000
        # Delete it from memory
        rm -fr $1
        logger "$0: $1 thrown away"
}

# Encrypt specific volume
# Input: volume name, e.g. sdb
encvol () {
	VRANDKEY=`randkey $RKEY.$1`
	logger "$0: luksFormat $VRANDKEY"
    cryptsetup -d $VRANDKEY luksFormat /dev/$1 << ENDL
YES
ENDL
    logger "$0: luksOpen $VRANDKEY"
    cryptsetup -d $VRANDKEY luksOpen /dev/$1 $1-pv
    wipekey $VRANDKEY
}

# Create encrypted drive based on local ephemeral storage.
# Key is randomly generated and stored on ramdisk temporaily, once encryption setup process has completed it is deleted immediately
# LVM is used to stripe together multiple volumes into a single encrypted volume.
# Input: No input
encdrives () {
	# Lets get a list of all our ephemeral drives
	export DRIVES=$(curl -s http://169.254.169.254/latest/meta-data/block-device-mapping/ | egrep -v "ami|root")
	#DRIVES="sdxx sdzz"
	if [ "$DRIVES" = "" ]; then
	        logger "$0: No ephemeral drives found"
	        exit 1
	fi

	# Lets setup some randomise names to make the process more obscure
	RDISK=/`randstring 8`			# Ramdisk path
	RKEY=$RDISK/`randstring 16`		# Random key name prefix
	ENCMOUNT=/tmp/`randstring 16`	# Encrypted volume mount point
	VGNAME=`randstring 4`			# Volume Group Name
	LVNAME=`randstring 4`			# Logical Volume Name

	# Setup the ramdisk
	umount $RDISK
	mkdir -p $RDISK
	mount -o size=10m -t tmpfs none $RDISK 	# Lets use tmpfs for our ramdisk
	logger "$0: Mounted ram disk $RDISK"

	# Find all volumes for ephemeral drives
	# Encrypt all volumes with a different key
	# Create physical volume to construct volume group
	export VGVOL=""
	for DRIVE in $DRIVES
	do
	        # Get the actual volume name, umount it and setup encryption on volume
	        VOL=$(curl -s http://169.254.169.254/latest/meta-data/block-device-mapping/$DRIVE/)
	        #VOL=$DRIVE.$$
	        umount /dev/$VOL
	        encvol $VOL

	        # Create a physical volume to use with LVM
	        pvcreate /dev/mapper/$VOL-pv
	        VGVOL=$(echo $VGVOL "/dev/mapper/$VOL-pv")
	done

	# Unmount the ramdisk
	umount $RDISK

	# Setup the LVM with a VG spanning all volumes
	logger "$0: $VGNAME - $VGVOL"
	vgcreate $VGNAME $VGVOL

	# Create LV at maximum size of VG
	lvcreate -n $LVNAME -l 100%FREE $VGNAME
	logger "$0: created VG:$VGNAME - LV:$LVNAME"

	# Create new EXT4 filesystem on LV
	mkfs.ext4 -m 0 /dev/$VGNAME/$LVNAME
	logger "$0: Created Filesystem /dev/$VGNAME/$LVNAME"
	mkdir -p $ENCMOUNT
	chmod 0000 $ENCMOUNT

	# Mount volume on random path
	mount /dev/$VGNAME/$LVNAME $ENCMOUNT
	logger "$0: mounted $ENCMOUNT"
}

# Secure environment
# Input: No input
secure () {
	logger "$0: secure environment"
	# Run setup scripts to harden OS as per SOE and preapre this instance
	# for its specific purpose, e.g. remove all login rights
}

# Install packages required for operation
# Input: No input
setupenv () {
	logger "$0: install packages"
	# packages can be installed either via package manager or
	# downloaded from central repository
}

# Setup Environment
# Input: No input
instapp () {
	logger "$0: install application code"
	# Download the latest version of the code from central repository,
	# install into application path and setup ready for use
}

# Start Application
# Input: No input
startapp () {
	logger "$0: start application"
	# Most likely that this function will initiate a cronjob for a process checker
	# which in turn will start the java worker process to poll for new files
}

# Main function
# call required functions required to setup machine ready for processing secure data
logger "$0: Lets get started"
secure
setupenv
encdrives
instapp
startapp
logger "$0: All done, lets go home"
exit 0
