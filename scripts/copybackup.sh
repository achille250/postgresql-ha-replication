#!/bin/sh
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin
umask 077


cd /Postgres/BK_PRIMARY_NW
#list the last backup
a=`ls -lrth | tail -1   | awk '{print $9}' `
#copy the last backup to another location

scp -p  $a CHANGE_ME_HOST:/Postgres/Base_BK 2>>/var/log/walcopy.log

# Setup passwordless SSH to all target nodes (source server and bkp server)
# on source server: 
# ssh-keygen -t rsa # press enter on all prompts
# copy the ssh-key to backup server
#ssh-copy-id -i ~/.ssh/id_rsa [backupserver IP address]