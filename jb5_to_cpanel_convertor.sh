#!/bin/bash
# 
# Created by TheLazyAdmin, https://thelazyadmin.blog
#
# ** USE AT YOUR OWN RISK ** 
# Downloaded from: https://thelazyadmin.blog/convert-jetbackup-to-cpanel

# TheLazyAdmin indicated to use this license:
# https://thelazyadmin.blog/convert-jetbackup-to-cpanel#comment-3240
# 
# MIT License
# 
# Copyright (c) 2022 TheLazyAdmin
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

function print_help {
	echo "
Example for manual usage:
jb5_to_cpanel_convertor.sh {JETBACKUP5_BACKUP} {DESTINATION_ARCHIVE}

{JETBACKUP5_BACKUP}   = Source JetBackup file
{DESTINATION_ARCHIVE} = Destination folder for cPanel backup, defaults to /home/

jb5_to_cpanel_convertor.sh /usr/local/jetapps/usr/jetbackup5/downloads/download_jb5user_1663238955_28117.tar.gz /root/cpanel_structure
"
	exit 0
}

function message {
	echo "";
	echo "$1";
	echo "";
	[[ -z $2 ]] && print_help
	exit
}

function untar() {
	BACKUP_PATH=$1
	DESTINATION_PATH=$2
	tar -xf $BACKUP_PATH -C $DESTINATION_PATH
	CODE=$?
	[[ $CODE -gt 0  ]] && message "Unable to untar the file $BACKUP_PATH" 1
}

function extract() {
	FILE_PATH=$1
	gunzip $FILE_PATH
	CODE=$?
	[[ $CODE -gt 0 ]] && message "Unable to extract files" 1
}

function move_dir() {
		echo "Migrating $1"
		SOURCE=$1
		DESTINATION=$2
		mv $SOURCE $DESTINATION
		CODE=$?
		[[ $CODE -gt 0 ]] && message "error occurred" 1
}

function archive() {
		TAR_NAME=$1
		
		echo "Creating archive $UNZIP_DESTINATION/$TAR_NAME"
		
		cd $UNZIP_DESTINATION
		tar -czf "$TAR_NAME" cpmove-"$ACCOUNT_NAME" >/dev/null 2>&1
		CODE=$?
		[[ $CODE != 0 ]] && message "Unable to create tar file" 1
}

function create_ftp_account() {
	DIRECTORY_PATH=$1
	CONFIG_PATH=$2
	HOMEDIR=$( cat $CONFIG_PATH/meta/homedir_paths )
	USER=$( ls $CONFIG_PATH/cp/)
	
	for FILE in $(ls $DIRECTORY_PATH | grep -iE "\.acct$"); do
		USERNAME=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=name: )(\w\D+)')
		PASSWORD=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=password: )([A-Za-z0-9!@#$%^&*,()\/\\.])+')
		PUBLIC_HTML_PATH=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=path: )([A-Za-z0-9\/_.-]+)')
		echo "Creating FTP account $USERNAME";
		printf "$USERNAME:$PASSWORD:0:0:$USER:$HOMEDIR/$PUBLIC_HTML_PATH:/bin/ftpsh" >> $CPANEL_DIRECTORY/proftpdpasswd
	done
}

function create_mysql_file() {
	DIRECTORY_PATH=$1
	SQL_FILE_PATH=$2
	
	for FILE in $(ls $DIRECTORY_PATH | grep -iE "\.user$"); do
		USERNAME=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=name: )([a-zA-Z0-9!@#$%^&*(\)\_\.-]+)')
		DATABASE=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=database `)([_a-zA-Z0-9]+)')
		USER=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=name: )([a-zA-Z0-9!#$%^&*(\)\_\.]+)')
		DOMAIN=$(echo $USERNAME | grep -Po '(?<=@)(.*)$')
		PASSWORD=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=password: )([a-zA-Z0-9*]+)')
		PERMISSIONS=$(cat $DIRECTORY_PATH/$FILE | grep -Po '(?<=:)[A-Z ,]+$')
		
		echo "Creating DB $DATABASE"
		echo "Adding DB user $USER"
		
		echo "GRANT USAGE ON *.* TO '$USER'@'$DOMAIN' IDENTIFIED BY PASSWORD '$PASSWORD';" >> $SQL_FILE_PATH
		echo "GRANT$PERMISSIONS ON \`$DATABASE\`.* TO '$USER'@'$DOMAIN';" >> $SQL_FILE_PATH
	done
}

function create_email_account() {
	BACKUP_EMAIL_PATH=$1
	DESTINATION_EMAIL_PATH=$2
	DOMAIN_USER=$( cat $CPANEL_DIRECTORY/cp/$ACCOUNT_NAME | grep -Po '(?<=DNS=)([A-Za-z0-9-.]+)')
	
	echo "Creating email accounts for $DOMAIN_USER"
	
	for JSON_FILE in $(ls $BACKUP_EMAIL_PATH | grep -iE "\.conf$"); do
		PASSWORD=$(cat $BACKUP_EMAIL_PATH/$JSON_FILE | grep -Po '(?<=,"password":")([a-zA-Z0-9\=,]+)')
		DECODED_PASSWORD=$(echo $PASSWORD | base64 --decode )
		printf $DOMAIN_USER:$DECODED_PASSWORD >> $DESTINATION_EMAIL_PATH/$DOMAIN_USER/shadow
	done
}

FILE_PATH=$1
DES_PATH=$2
UNZIP_DESTINATION=$DES_PATH/jb5_migrate_$RANDOM
FETCH_DOWNLOAD=$3

[[ $DES_PATH == "/" ]] && message "Error :: Don't use root folder as destination"

BACKUP_PATH=$(echo $FILE_PATH)
ACCOUNT_NAME=$(echo $FILE_PATH |  grep -oP '(?<=download_)([^_]+)')
! [[ -f $BACKUP_PATH ]] && message "Invalid file provided"

echo "Backup path found: $BACKUP_PATH"
echo "Account name found: $ACCOUNT_NAME"
echo "Creating folder $UNZIP_DESTINATION"

mkdir -p $UNZIP_DESTINATION
! [[ -d $UNZIP_DESTINATION ]] && message "Destination directory error"

echo "Untaring $BACKUP_PATH into $UNZIP_DESTINATION"
untar $BACKUP_PATH $UNZIP_DESTINATION

! [[ -d $UNZIP_DESTINATION/backup ]] && message "JetBackup5 backup directory $UNZIP_DESTINATION/backup not found" 1

CPANEL_DIRECTORY=$UNZIP_DESTINATION/cpmove-$ACCOUNT_NAME
JB5_BACKUP=$UNZIP_DESTINATION/backup

echo "Converting account '$ACCOUNT_NAME'"
echo "Working folder: $CPANEL_DIRECTORY"

if ! [[ -d $JB5_BACKUP/config ]]; then
	message "The backup not contain the config directory"
else
	move_dir "$JB5_BACKUP/config" "$CPANEL_DIRECTORY/"
fi

if [[ -d $JB5_BACKUP/homedir ]]; then
	 if ! [[ -d $CPANEL_DIRECTORY/homedir ]]; then
		move_dir "$JB5_BACKUP/homedir" "$CPANEL_DIRECTORY"
	 else
		rsync -ar "$JB5_BACKUP/homedir" "$CPANEL_DIRECTORY"
	 fi
fi

if [[ -d $JB5_BACKUP/database ]] ; then
	move_dir "$JB5_BACKUP/database/*" "$CPANEL_DIRECTORY/mysql"
	extract "$CPANEL_DIRECTORY/mysql/*"
fi

[[ -d $JB5_BACKUP/database_user ]] && create_mysql_file "$JB5_BACKUP/database_user" "$CPANEL_DIRECTORY/mysql.sql"

if [[ -d $JB5_BACKUP/email ]]; then
	move_dir "$JB5_BACKUP/email" "$CPANEL_DIRECTORY/homedir/mail"
	[[ -d $JB5_BACKUP/jetbackup.configs/email ]] && create_email_account "$JB5_BACKUP/jetbackup.configs/email" "$CPANEL_DIRECTORY/homedir/etc" "$ACCOUNT_NAME"
fi

[[ -d $JB5_BACKUP/ftp ]] && create_ftp_account "$JB5_BACKUP/ftp" "$CPANEL_DIRECTORY"

echo "Creating final cPanel backup archive...";
archive "cpmove-$ACCOUNT_NAME.tar.gz"
echo "Converting Done!"
echo "You can safely remove working folder at: $JB5_BACKUP"
echo "Your cPanel backup location: $UNZIP_DESTINATION/cpmove-$ACCOUNT_NAME.tar.gz"

