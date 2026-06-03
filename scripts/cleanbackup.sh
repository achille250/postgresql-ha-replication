#!/bin/sh
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin
umask 077
####################################################
## Variables declaration                           #
####################################################
cd /u02/basebackups
USED_SIZE=$(df -Ph | grep '/u02' | awk {'print $5'})
MAX_SIZE=75%
OLDFILE=`ls -tr  | head -n 1`

NEWFILE=`ls -lrth | tail -1   | awk '{print $9}'`




###################################################
## Logic starts here                              #
###################################################





#If the back up directory has reached the maximum size

if [ ${USED_SIZE%?} -ge ${MAX_SIZE%?} ]; then

    echo "$(date): Backup dir has reached: ${MAX_SIZE}" >> /home/logs/notification.log

    rm -fr "${OLDFILE}"

    echo "$(date): Removed ${OLDFILE} as size Reached: ${MAX_SIZE}" >> /home/logs/notification.log

   
 

#    echo "$(date): Successfully copied this file: ${NEWFILE}" >> /home/logs/copied.log

    exit 1

else

   echo "$(date): No backup Removed as Backup dir is less than: ${MAX_SIZE}" >> /home/logs/notification.log

        exit 1
fi



