set -eu
mode='__MODE__'
source_disk=/dev/disk/azure/scsi1/lun0
restore_disk=/dev/disk/azure/scsi1/lun1
original='CSL Day 51 harmless recovery validation.'
mkdir -p /mnt/csl-source /mnt/csl-restored
test -b "$source_disk"
test "$(blockdev --getsize64 "$source_disk")" = 4294967296
if [ "$mode" = seed ]; then
  fs=$(blkid -s TYPE -o value "$source_disk" || true)
  if [ -z "$fs" ]; then mkfs.ext4 -q "$source_disk"; else test "$fs" = ext4; fi
fi
mountpoint -q /mnt/csl-source || mount "$source_disk" /mnt/csl-source
test "$(findmnt -n -o MAJ:MIN /mnt/csl-source)" = "$(lsblk -dn -o MAJ:MIN "$source_disk")"
case "$mode" in
 seed) printf '%s\n' "$original" > /mnt/csl-source/payload.txt; sync ;;
 change) sha256sum /mnt/csl-source/payload.txt; printf '%s\n' 'CHANGED AFTER BACKUP: harmless drill.' > /mnt/csl-source/payload.txt; sync ;;
 verify)
   test -b "$restore_disk"
   mount -o ro,noload "$restore_disk" /mnt/csl-restored
   trap 'umount /mnt/csl-restored' EXIT
   expected=$(printf '%s\n' "$original" | sha256sum | cut -d ' ' -f 1)
   actual=$(sha256sum /mnt/csl-restored/payload.txt | cut -d ' ' -f 1)
   test "$expected" = "$actual"
   if [ '__REQUIRE_CHANGED__' = 1 ]; then
     current=$(sha256sum /mnt/csl-source/payload.txt | cut -d ' ' -f 1)
     test "$current" != "$actual"
   fi
   printf 'Expected and restored SHA256: %s\n' "$actual"
   sha256sum /mnt/csl-source/payload.txt
   ;;
 *) echo 'Unknown operation' >&2; exit 2 ;;
esac
sha256sum /mnt/csl-source/payload.txt
printf 'CSL_%s_PASS\n' "$mode"
