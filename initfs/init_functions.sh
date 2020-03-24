#!/bin/sh
IP=172.16.42.1
LOGS="/mnt/userdata/media/0/Mainline"

setup_log() {
		echo "NOTE: All output from the initramfs gets redirected to :"
		echo "/init.log"

		# Start redirect
		exec >/init.log 2>&1
		echo "### Initramfs Debug Tool ###"
}

mount_proc_sys_dev() {
	# mdev
	mount -t proc -o nodev,noexec,nosuid proc /proc || echo "Couldn't mount /proc"
	mount -t sysfs -o nodev,noexec,nosuid sysfs /sys || echo "Couldn't mount /sys"

	mkdir /config
	mount -t  configfs -o nodev,noexec,nosuid configfs /config || echo "Couldn't mount /config"

	mkdir -p /dev/pts || echo "Couldn't create directory /dev/pts"
	mount -t devpts devpts /dev/pts || echo "Couldn't mount /dev/pts"

	mkdir /run
}

setup_mdev() {
	echo /sbin/mdev > /proc/sys/kernel/hotplug
	mdev -s
}

setup_usb_network() {
	CONFIGFS=/config/usb_gadget

	if ! [ -e "$CONFIGFS" ]; then
		echo "  /config/usb_gadget does not exist, skipping configfs usb gadget"
		return
	fi

	echo "  Setting up an USB gadget through configfs"
	echo "Create an usb gadet configuration"
	mkdir $CONFIGFS/g1 || echo "  Couldn't create $CONFIGFS/g1"
	printf "%s" "0x18D1" >"$CONFIGFS/g1/idVendor"
	printf "%s" "0xD001" >"$CONFIGFS/g1/idProduct"

	echo "Create english (0x409) strings"
	mkdir $CONFIGFS/g1/strings/0x409 || echo "  Couldn't create $CONFIGFS/g1/strings/0x409"
	echo "postmarketOS" > "$CONFIGFS/g1/strings/0x409/manufacturer"
	echo "Debug network interface" > "$CONFIGFS/g1/strings/0x409/product"
	echo "7d97ad74" > "$CONFIGFS/g1/strings/0x409/serialnumber"

	echo "Create ncm function"
	mkdir $CONFIGFS/g1/functions/ncm.usb0 || echo "  Couldn't create $CONFIGFS/g1/functions/ncm.usb0"

	echo "Create configuration instance for the gadget"
	mkdir $CONFIGFS/g1/configs/c.1 || echo "  Couldn't create $CONFIGFS/g1/configs/c.1"
	mkdir $CONFIGFS/g1/configs/c.1/strings/0x409 || echo "  Couldn't create $CONFIGFS/g1/configs/c.1/strings/0x409"
	printf "%s" "ncm" > $CONFIGFS/g1/configs/c.1/strings/0x409/configuration || echo "  Couldn't write configration name"

	echo "Link the ncm instance to the configuration"
	ln -s $CONFIGFS/g1/functions/ncm.usb0 $CONFIGFS/g1/configs/c.1 || echo "  Couldn't symlink ncm.usb0"

	echo "Calling the usb controller"
	echo "a800000.dwc3" > "$CONFIGFS/g1/UDC"
}

start_udhcpd() {
	touch /etc/udhcpd.conf
	ifconfig usb0 "$IP"
}

start_telnetd() {
	mkdir -p /dev/shm
	mount -t tmpfs tmpfs /dev/shm
	telnetd -l /bin/sh
}

mount_userdata_partition() {
	mkdir /mnt/userdata
	mount /dev/sda17 /mnt/userdata || echo "Couldn't mount userdata partition!" > /dev/kmsg
}

log() {
	# Print messages on device screen
	echo "# $1" > /dev/kmsg
	eval $1 > /dev/kmsg

	# Save log to file on internal storage
	if [ ! -z "$2" ]; then
		echo "# $1" > "$LOGS/$2.log"
		eval $1 >> "$LOGS/$2.log" # e.g. "$LOGS/uname.log"
		echo -e "========================\n" >> "$LOGS/$2.log"
	fi
}

copy_logs_to_userdata() {
	# Init
	rm -r $LOGS
	mkdir -p $LOGS

	# dmesg / kmsg
	dmesg > $LOGS/kmsg.log && echo "Copied dmesg output to kmsg.log, now this is epic cx" > /dev/kmsg

	# /init.log
	cp /init.log $LOGS/ && echo "Copied /init.log to internal storage." > /dev/kmsg || echo "Couldn't copy init.log to userdata!" > /dev/kmsg

	# any other misc commands
	log "uname -a" "uname"
	# log "ifconfig -a" "ifconfig"
	# log "lsusb -tv" "lsusb"
	# log "i2cdetect -l" "i2cdetect"
	# #log "lsmod" "lsmod"
	# log "cat /proc/cmdline" "cmdline"
	# #log "ls /dev" "ls"
	# log "dmesg | grep -i ufs"
	# log "uname -a" "" 

	#log "lspci -vvv" "lspci"
	#log "modprobe dwc3" "modprobe"

	# dyndbg
	mount -t debugfs none /sys/kernel/debug/
	cat /sys/kernel/debug/dynamic_debug/control > $LOGS/dyndbg.log && echo "Copied dynamic_debug log to internal storage." > /dev/kmsg || echo "Couldn't copy dynamic_debug log to internal storage!" > /dev/kmsg
}
