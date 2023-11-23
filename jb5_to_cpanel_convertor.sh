#!/bin/bash
# Convert the supplied JetBackup 5 backup file to a cPanel-compatible backup.
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

function Error {
	echo ""
	echo "$1"
	exit 1
}

function ErrorHelp {
	echo ""
	echo "$1"
	echo "
Example for manual usage:
jb5_to_cpanel_convertor.sh {JETBACKUP5_BACKUP} {DESTINATION_ARCHIVE}

{JETBACKUP5_BACKUP}   = Source JetBackup file
{DESTINATION_ARCHIVE} = Destination folder for cPanel backup, defaults to /home/

e.g. 
jb5_to_cpanel_convertor.sh /home/download_jb5user_1663238955_28117.tar.gz
"
	exit 1
}

function Untar() {
	BackupPath="$1"
	DestPath="$2"
	tar -xf "$BackupPath" -C "$DestPath"
	Err=$?
	[[ $Err -gt 0  ]] && Error "Unable to untar the file '$BackupPath'"
}

function Extract() {
	FilePath="$1"
	gunzip $FilePath	# FilePath not quoted so can expand wildcard
	Err=$?
	[[ $Err -gt 0 ]] && Error "Unable to extract files"
}

function MoveDir() {
	echo "Migrating $1"
	Src="$1"
	Dst="$2"
	mv $Src "$Dst"		# Src not quoted so can expand wildcard
	Err=$?
	[[ $Err -gt 0 ]] && Error "error occurred"
}

function Archive() {
	TarName="$1"
	echo "Creating archive '$UnzipDest/$TarName'"
	
	cd "$UnzipDest"
	tar -czf "$TarName" "cpmove-$AccountName" >/dev/null 2>&1
	Err=$?
	[[ $Err != 0 ]] && Error "Unable to create tar file"
}

function CreateFTPaccount() {
	DirPath="$1"
	ConfigPath="$2"
	HomeDir="$( cat "$ConfigPath/meta/homedir_paths" )"
	User="$( ls "$ConfigPath/cp/")"
	
	for FILE in $(ls "$DirPath" | grep -iE "\.acct$"); do
		Username="$(cat "$DirPath/$FILE" | grep -Po '(?<=name: )(\w\D+)')"
		Password="$(cat "$DirPath/$FILE" | grep -Po '(?<=password: )([A-Za-z0-9!@#$%^&*,()\/\\.])+')"
		WebRootPath="$(cat "$DirPath/$FILE" | grep -Po '(?<=path: )([A-Za-z0-9\/_.-]+)')"
		echo "Creating FTP account '$Username'";
		printf "$Username:$Password:0:0:$User:$HomeDir/$WebRootPath:/bin/ftpsh" >> $CPanelDir/proftpdpasswd
	done
}

function CreateMySQLfile() {
	DirPath="$1"
	SQL_FilePath="$2"
	
	for FILE in $(ls "$DirPath" | grep -iE "\.user$"); do
		Username="$(cat "$DirPath/$FILE" | grep -Po '(?<=name: )([a-zA-Z0-9!@#$%^&*(\)\_\.-]+)')"
		Database="$(cat "$DirPath/$FILE" | grep -Po '(?<=database `)([_a-zA-Z0-9]+)')"
		User="$(cat "$DirPath/$FILE" | grep -Po '(?<=name: )([a-zA-Z0-9!#$%^&*(\)\_\.]+)')"
		Domain="$(echo "$Username" | grep -Po '(?<=@)(.*)$')"
		Password="$(cat "$DirPath/$FILE" | grep -Po '(?<=password: )([a-zA-Z0-9*]+)')"
		Permissions="$(cat "$DirPath/$FILE" | grep -Po '(?<=:)[A-Z ,]+$')"
		
		echo "Creating DB '$Database'"
		echo "Adding DB user '$User'"
		
		echo "GRANT USAGE ON *.* TO '$User'@'$Domain' IDENTIFIED BY Password '$Password';" >> $SQL_FilePath
		echo "GRANT$Permissions ON \`$Database\`.* TO '$User'@'$Domain';" >> $SQL_FilePath
	done
}

function CreateEmailAccount() {
	BackupEmailPath="$1"
	DestEmailPath="$2"
	DomainUser="$( cat "$CPanelDir/cp/$AccountName" | grep -Po '(?<=DNS=)([A-Za-z0-9-.]+)')"
	
	echo "Creating email accounts for '$DomainUser'"
	
	for JSON_FILE in $(ls "$BackupEmailPath" | grep -iE "\.conf$"); do
		Password="$(cat "$BackupEmailPath/$JSON_FILE" | grep -Po '(?<=,"password":")([a-zA-Z0-9\=,]+)')"
		DecodedPassword="$(echo "$Password" | base64 --decode )"
		printf "$DomainUser:$DecodedPassword" >> "$DestEmailPath/$DomainUser/shadow"
	done
}

# Parse arguments
FilePath="$1"
DestDir="$2"
UnzipDest="$DestDir/jb5_migrate_$RANDOM"

[[ "$DestDir" == "/" ]] && Error "Error :: Don't use root folder as destination"

BackupPath=$(echo "$FilePath")
AccountName=$(echo "$FilePath" |  grep -oP '(?<=download_)([^_]+)')
! [[ -f "$BackupPath" ]] && Error "Invalid file provided"

echo "Backup path found: '$BackupPath'"
echo "Account name found: '$AccountName'"
echo "Creating folder '$UnzipDest'"

mkdir -p "$UnzipDest"
! [[ -d "$UnzipDest" ]] && Error "Destination directory error"

echo "Untaring '$BackupPath' into '$UnzipDest'"
Untar "$BackupPath" "$UnzipDest"

! [[ -d "$UnzipDest/backup" ]] && Error "JetBackup5 backup directory '$UnzipDest/backup' not found"

CPanelDir="$UnzipDest/cpmove-$AccountName"
JB5Backup="$UnzipDest/backup"

echo "Converting account '$AccountName'"
echo "Working folder: '$CPanelDir'"

if ! [[ -d "$JB5Backup/config" ]]; then
	Error "The backup not contain the config directory"
else
	MoveDir "$JB5Backup/config" "$CPanelDir/"
fi

if [[ -d "$JB5Backup/homedir" ]]; then
	if ! [[ -d "$CPanelDir/homedir" ]]; then
		MoveDir "$JB5Backup/homedir" "$CPanelDir"
	else
		rsync -ar "$JB5Backup/homedir" "$CPanelDir"
	fi
fi

if [[ -d "$JB5Backup/database" ]] ; then
	MoveDir "$JB5Backup/database/*" "$CPanelDir/mysql"
	Extract "$CPanelDir/mysql/*"
fi

[[ -d "$JB5Backup/database_user" ]] && CreateMySQLfile "$JB5Backup/database_user" "$CPanelDir/mysql.sql"

if [[ -d "$JB5Backup/email" ]]; then
	MoveDir "$JB5Backup/email" "$CPanelDir/homedir/mail"
	[[ -d "$JB5Backup/jetbackup.configs/email" ]] && CreateEmailAccount "$JB5Backup/jetbackup.configs/email" "$CPanelDir/homedir/etc" "$AccountName"
fi

[[ -d "$JB5Backup/ftp" ]] && CreateFTPaccount "$JB5Backup/ftp" "$CPanelDir"

echo "Creating final cPanel backup archive...";
Archive "cpmove-$AccountName.tar.gz"
echo "Converting Done!"
echo "You can safely remove working folder at: '$JB5Backup'"
echo "Your cPanel backup location: $UnzipDest/cpmove-$AccountName.tar.gz"

