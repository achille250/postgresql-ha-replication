#!/bin/sh
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin
umask 077
#clean wall backup older than 3 days
directory="/U02/Archive"
# Specify the number of days(3 days for my case set yours)
days_threshold=3
cd /U02/Archive

#For files older than 3days, you need -mtime +2   not -mtime +3
#list file over than 3 days
#find /U02/Archive -maxdepth 1 -mtime +2  -ls
#For files older than 3 days, you need -mtime +2   not -mtime +2

#delete file older than 3days
find /U02/Archive -maxdepth 1 -mtime +2  -type f -delete
echo "Files older than $days_threshold days have been deleted from $directory." >> /home/logs/notification.log

# Use the 'find' command to locate files older than the specified threshold
# and then delete them with the 'rm' command
#-mtime stand for last modified time
# if you need to remove or list files use -f for directory use -d
