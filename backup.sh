#!/bin/sh
# Starts a duplicity backup to the vollmar backup FTP.
# © 2011 Michael Stapelberg (see also: LICENSE)

# Include common environment (passwords, path, …)
. $(dirname $0)/common.sh

################################################################################
# Full backup of this host (VM host)
################################################################################

echo "Backing up host"

# Run an incremental backup of / daily, run a full backup every week. Only use
# files on the file system /, so /proc, /sys and other dynamic stuff is
# excluded. Also, we specifically exclude the *contents* of /tmp, which is on
# the same filesystem.
/usr/bin/duplicity incr \
	--exclude-other-filesystems \
	--exclude '/tmp/*' \
	--full-if-older-than 7D \
	--gpg-options '--compress-algo=zlib --compress-level 2' \
	/ \
	"$BASEPATH/in-root"

# Remove all but the last 4 full backups. This keeps a bit over one month of
# history (since we force a full backup every 7 days).
/usr/bin/duplicity remove-all-but-n-full 4 "$BASEPATH/in-root"

# Log status.
/usr/bin/duplicity collection-status "$BASEPATH/in-root"

################################################################################
# Backups for each VM
################################################################################

# trap handler to unmount the LVMs in case anything goes wrong.
cleanup() {
	/root/bin/xen-lvm-snapshot/foreach-domu.sh unmount >/dev/null
}

trap 'cleanup' EXIT

# Mount all the VMs to /mnt/snap_*
/root/bin/xen-lvm-snapshot/foreach-domu.sh mount >/dev/null

LVS=$(/sbin/lvs --separator / --noheadings -o vg_name,lv_name 2>&- | /usr/bin/tr -d ' ' | /bin/grep '/domu-')
for LV in ${LVS}
do
	# Reduce the name from vg/domu-<name> to <name>
	DOMU=$(echo "$LV" | sed 's,[^/]*/domu-,,g')
	echo "Backing up VM $DOMU"

	# Run an incremental backup of / daily, run a full backup every week. Only use
	# files on the file system /, so /proc, /sys and other dynamic stuff is
	# excluded. Also, we specifically exclude the *contents* of /tmp, which is on
	# the same filesystem.
	/usr/bin/duplicity incr \
		--exclude-other-filesystems \
		--exclude "/mnt/snap_$DOMU/tmp/*" \
		--full-if-older-than 7D \
		--gpg-options '--compress-algo=zlib --compress-level 2' \
		/mnt/snap_$DOMU/ \
		"$BASEPATH/vm-$DOMU"

	# Remove all but the last 4 full backups. This keeps a bit over one month of
	# history (since we force a full backup every 7 days).
	/usr/bin/duplicity remove-all-but-n-full 4 "$BASEPATH/vm-$DOMU"

	# Log status.
	/usr/bin/duplicity collection-status "$BASEPATH/vm-$DOMU"
done
