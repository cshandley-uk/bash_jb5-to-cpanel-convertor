#!/bin/bash
# Convert the supplied JetBackup 5 backup file to a cPanel-compatible backup.
# 
# Originally created by TheLazyAdmin, https://thelazyadmin.blog
#
# ** USE AT YOUR OWN RISK ** 

# MIT License
# 
# Copyright (c) 2022 TheLazyAdmin
# Copyright (c) 2023,2024 Christopher Handley
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
How to use:
jb5_to_cpanel_convertor.sh JETBACKUP5_BACKUP [DESTINATION_FOLDER]

JETBACKUP5_BACKUP  = Source JetBackup file
DESTINATION_FOLDER = Optional destination folder for cPanel backup, 
                     defaults to /home/, if you are root, otherwise to ~/

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
	Src="$1"
	Dst="$2"
	echo "Converting folder '$Src'"
	
	mv $Src "$Dst"		# Src not quoted so can expand wildcard
	Err=$?
	[[ $Err -gt 0 ]] && Error "An error occurred"
}

function Archive() {
	TarName="$1"
	echo "Creating archive '$DestDir/$TarName'"
	
	if [ -f "$DestDir/$TarName" ]; then rm "$DestDir/$TarName"; fi	# Ensure create a new archive from scratch
	cd "$UnzipDest" || Error "Failed to CD to '$UnzipDest'"
	tar -czf "$DestDir/$TarName" "cpmove-$AccountName" >/dev/null 2>&1
	Err=$?
	[[ $Err != 0 ]] && Error "Unable to create tar file"
}

function CreateFTPaccount() {
	DirPath="$1"
	ConfigPath="$2"
	HomeDir="$( cat "$ConfigPath/meta/homedir_paths" )"
	User="$( ls "$ConfigPath/cp/")"
	
	for FILE in $(ls -1 "$DirPath" | grep -iE "\.acct$"); do
		Username="$(grep -Po '(?<=name: )(\w\D+)' "$DirPath/$FILE")"
		Password="$(grep -Po '(?<=password: )([A-Za-z0-9!@#$%^&*,()\/\\.])+' "$DirPath/$FILE")"
		WebRootPath="$(grep -Po '(?<=path: )([A-Za-z0-9\/_.-]+)' "$DirPath/$FILE")"
		echo "Creating FTP account '$Username'";
		printf "%s:%s:0:0:%s:%s/%s:/bin/ftpsh" "$Username" "$Password" "$User" "$HomeDir" "$WebRootPath" >> "$CPanelDir/proftpdpasswd"
	done
}

function CreateMySQLfile() {
	DirPath="$1"
	SQL_FilePath="$2"
	
	for FILE in $(ls -1 "$DirPath" | grep -iE "\.user$"); do
		Username="$(grep -Po '(?<=name: )([a-zA-Z0-9!@#$%^&*(\)\_\.-]+)' "$DirPath/$FILE")"
		Database="$(grep -Po '(?<=database `)([_a-zA-Z0-9]+)' "$DirPath/$FILE")"
		User="$(grep -Po '(?<=name: )([a-zA-Z0-9!#$%^&*(\)\_\.]+)' "$DirPath/$FILE")"
		Domain="$(echo "$Username" | grep -Po '(?<=@)(.*)$')"
		Password="$(grep -Po '(?<=password: )([a-zA-Z0-9*]+)' "$DirPath/$FILE")"
		Permissions="$(grep -Po '(?<=:)[A-Z ,]+$' "$DirPath/$FILE")"
		
		echo "Creating DB '$Database' & adding DB user '$User'"
		
		echo "GRANT USAGE ON *.* TO '$User'@'$Domain' IDENTIFIED BY PASSWORD '$Password';" >> "$SQL_FilePath"
		echo "GRANT$Permissions ON \`$Database\`.* TO '$User'@'$Domain';" >> "$SQL_FilePath"
	done
}

function CreateEmailAccount() {
	BackupEmailPath="$1"
	DestEmailPath="$2"
	
	echo "Creating email accounts"
	
	for JSON_FILE in $(ls -1 "$BackupEmailPath" | grep -iE "\.conf$"); do
		JsonFile="$BackupEmailPath/$JSON_FILE"
		MailUser="$(jq -r '.account' "$JsonFile" | base64 --decode)"
		MailDomain="$(jq -r '.domain' "$JsonFile" | base64 --decode)"
		MailPassword="$(jq -r '.password' "$JsonFile" | base64 --decode)"
		echo "${MailUser}:${MailPassword}:::::::" >>"$DestEmailPath/${MailDomain}/shadow"
	done
}

function CreateDomains() {
	DirPath="$1"
	ConfigPath="$2"
	
	echo "Creating domains"
	
	# find primary domain
	PrimaryDomain=""
	for JSON_FILE in "$DirPath"/*.conf; do
		Domain="$(jq -r '.domain' "$JSON_FILE" | base64 --decode)"
		Type="$(jq -r '.type' "$JSON_FILE" | base64 --decode)"
		if [ "$Type" -eq 1 ]; then
			PrimaryDomain="$Domain"
		fi
	done
	if [ -z "$PrimaryDomain" ]; then Error "Failed to find the primary domain of account '$AccountName'"; fi
	# OR COULD JUST DO: PrimaryDomain="$( cat "$CPanelDir/cp/$AccountName" | grep -Po '(?<=DNS=)([A-Za-z0-9-.]+)')"
	
	# write info about sub-domains of the primary domain
	echo -n "" >"$ConfigPath"/sds
	echo -n "" >"$ConfigPath"/sds2
	for JSON_FILE in "$DirPath"/*.conf; do
		#WebRoot="$(jq -r '.public_dir' "$JSON_FILE" | base64 --decode)"
		Domain="$(jq -r '.domain' "$JSON_FILE" | base64 --decode)"
		Type="$(jq -r '.type' "$JSON_FILE" | base64 --decode)"
		if [[ "$Type" -eq 3 && "$Domain" == *.$PrimaryDomain ]]; then
			# (sub-domain)
			echo "	Adding sub-domain '$Domain'"
			echo "${Domain/./_}"         >>"$ConfigPath"/sds
			echo "${Domain/./_}=$Domain" >>"$ConfigPath"/sds2
		fi
	done
	
	# write info about addon & parked domains
	echo -n "" >"$ConfigPath"/addons
	echo -n "" >"$ConfigPath"/pds
	for JSON_FILE in "$DirPath"/*.conf; do
		#WebRoot="$(jq -r '.public_dir' "$JSON_FILE" | base64 --decode)"
		Domain="$(jq -r '.domain' "$JSON_FILE" | base64 --decode)"
		Type="$(jq -r '.type' "$JSON_FILE" | base64 --decode)"
		if [ "$Type" -eq 1 ]; then
			# (primary domain) so ignore it
			:
		elif [ "$Type" -eq 2 ]; then
			# (addon domain)
			echo "	Adding addon domain '$Domain'"
			echo "$Domain=${Domain/./_}.$PrimaryDomain" >>"$ConfigPath"/addons
			echo "${Domain/./_}.$PrimaryDomain"         >>"$ConfigPath"/sds
			echo "${Domain/./_}.$PrimaryDomain=$Domain" >>"$ConfigPath"/sds2
		
		elif [ "$Type" -eq 3 ]; then
			# (sub-domain) so ignore for the moment
			:
		
		elif [ "$Type" -eq 4 ]; then
			# (parked/alias domain)
			echo "$Domain" >>"$ConfigPath"/pds
		else
			# (unknown domain type)
			Error "Domain '$Domain' has unknown type '$Type'"
		fi
	done
	
	# write info about sub-domains that are NOT of the primary domain
	for JSON_FILE in "$DirPath"/*.conf; do
		#WebRoot="$(jq -r '.public_dir' "$JSON_FILE" | base64 --decode)"
		Domain="$(jq -r '.domain' "$JSON_FILE" | base64 --decode)"
		Type="$(jq -r '.type' "$JSON_FILE" | base64 --decode)"
		if [[ "$Type" -eq 3 && ! "$Domain" == *.$PrimaryDomain ]]; then
			# (sub-domain)
			echo "	Adding sub-domain '$Domain'"
			echo "${Domain/./_}"         >>"$ConfigPath"/sds
			echo "${Domain/./_}=$Domain" >>"$ConfigPath"/sds2
		fi
	done
}

function CreateSSLcerts() {
	DirPath="$1"
	ConfigPath="$2"
	
	echo "Creating SSL certifcates"
	
	# indicates the account will use WHM’s SSL Storage Manager feature (WHM » Home » SSL/TLS » SSL Storage Manager)
	# And without this, restoring the account will fail to install the SSL certificate, reporting "An error prevented adding a record of type “crt” ... That certificate is already installed as ..."
	touch "$ConfigPath"/has_sslstorage
	
	# with the above, the code below seems unnecessary, so I have disabled it
	return
	
	# loop through primary, addon & parked Domains
	for JSON_FILE in "$DirPath"/*.conf; do
		#WebRoot="$(jq -r '.public_dir' "$JSON_FILE" | base64 --decode)"
		Domain="$(jq -r '.domain' "$JSON_FILE" | base64 --decode)"
		Type="$(jq -r '.type' "$JSON_FILE" | base64 --decode)"
		if [[ "$Type" -eq 1 || "$Type" -eq 2 || "$Type" -eq 4 ]]; then
			echo "	Creating SSL cert for '$Domain'"
			#echo "# Domain='$Domain', Type=$Type (1/2/3/4=Primary/Addon/Sub/Parked)" >/dev/stderr
			echo -n "" >"$ConfigPath"/apache_tls/"$Domain"

			# for the Domain, get the Modulus of it's most recent certificate
			Modulus="$(yq -r ".files.certificate | to_entries | map(select(.value.\"subject.commonName\" == \"$Domain\")) | sort_by(.value.created) | reverse[0].value.modulus" "$ConfigPath"/homedir/ssl/ssl.db)"
			#echo "# domain has Modulus='$Modulus'" >/dev/stderr
			# get the name of the Key with the matching Modulus
			Key="$(yq -r ".files.key | to_entries | map(select(.value.modulus == \"$Modulus\"))[] | .key" "$ConfigPath"/homedir/ssl/ssl.db)"
			#echo "# modulus has Key='$Key'" >/dev/stderr
			# read the corresponding Key & append it to apache_tls/Domain
			cat "$ConfigPath"/homedir/ssl/keys/"$Key".key >>"$ConfigPath"/apache_tls/"$Domain"
			echo ""                                       >>"$ConfigPath"/apache_tls/"$Domain"
			
			# for the Domain, get the name of it's most recent Cert(ificate)
			Cert="$(yq -r ".files.certificate | to_entries | map(select(.value.\"subject.commonName\" == \"$Domain\")) | sort_by(.value.created) | reverse[0].key" "$ConfigPath"/homedir/ssl/ssl.db)"
			#echo "# domain has Cert='$Cert'" >/dev/stderr
			# read the Cert(ificate) & append it to apache_tls/Domain
			cat "$ConfigPath"/homedir/ssl/certs/"$Cert".crt >>"$ConfigPath"/apache_tls/"$Domain"
			echo ""                                         >>"$ConfigPath"/apache_tls/"$Domain"
			
			# I don't append the CA (Certificate Authority) bundle’s root node, as I can't find it in the JB5 backup.
			# BUT it might be unnecessary as "In most cases, you do not need to supply the CA bundle because the server will fetch it from a public repository"
		fi
	done
}

function CreateDNSZones() {
	DirPath="$1"
	ConfigPath="$2"
	
	echo "Creating DNS zones"
	
	for FILE in "$DirPath"/*.zone; do
		FileName="${FILE##*/}"
		DstFile="$ConfigPath/dnszones/${FileName%.*}.db"
		
		echo "	Creating '$DstFile'"
		mv "$FILE" "$DstFile"
		Err=$?
		[[ $Err -gt 0 ]] && Error "An error occurred"
	done
}

# Parse arguments
FilePath="$1"
DestDir="$2"

# Sanity check
! [[ -f "$FilePath" ]] && ErrorHelp "Invalid file provided"
[[ "$DestDir" == "/" ]] && ErrorHelp "Error :: Don't use root folder as destination"

# Default arguments
if [ -z "$DestDir" ]; then
	if [ "$(whoami)" == "root" ]; then
		DestDir=/home
	else
		DestDir=~
	fi
fi

# Extract username
#AccountName=$(echo "$FilePath" |  grep -oP '(?<=download_)([^_]+)')
AccountName="$(echo "${FilePath##*/}" | cut -d_ -f2)"

UnzipDest="$(mktemp --directory --tmpdir=/tmp "tmp_jb5_$AccountName.XXXXXXXX")"
BackupPath="$FilePath"

echo "Found backup path '$BackupPath'"
echo "Found account '$AccountName'"

echo "Creating temporary folder '$UnzipDest'"
mkdir -p "$UnzipDest"   || ErrorHelp "Destination directory error"
! [[ -d "$UnzipDest" ]] && ErrorHelp "Destination directory error"
# Ensure we always clean-up the temporary dir
Trap=":"
Trap="$Trap; rm -r '$UnzipDest'"
trap "trap '' EXIT SIGINT; $Trap" EXIT
trap "trap '' EXIT SIGINT; $Trap; exit 130" SIGINT
#echo "WARNING: Temp folder will NOT be deleted"

echo "Untaring '$BackupPath' into '$UnzipDest'"
Untar "$BackupPath" "$UnzipDest"
! [[ -d "$UnzipDest/backup" ]] && Error "JetBackup5 backup directory '$UnzipDest/backup' not found"

CPanelDir="$UnzipDest/cpmove-$AccountName"
JB5Backup="$UnzipDest/backup"

echo "Converting account '$AccountName'"
echo "Working folder '$CPanelDir'"

if ! [[ -d "$JB5Backup/config" ]]; then
	ErrorHelp "The backup does not contain the config directory"
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
	[[ -d "$JB5Backup/jetbackup.configs/email" ]] && CreateEmailAccount "$JB5Backup/jetbackup.configs/email" "$CPanelDir/homedir/etc"
fi

[[ -d "$JB5Backup/ftp" ]] && CreateFTPaccount "$JB5Backup/ftp" "$CPanelDir"

if [[ -d "$JB5Backup/jetbackup.configs/domain" ]]; then
	CreateDomains "$JB5Backup/jetbackup.configs/domain" "$CPanelDir"
	CreateSSLcerts "$JB5Backup/jetbackup.configs/domain" "$CPanelDir"
fi

if [[ -d "$JB5Backup/domain" ]]; then
	CreateDNSZones "$JB5Backup/domain" "$CPanelDir"
fi

echo "Creating final cPanel backup archive...";
Archive "cpmove-$AccountName.tar.gz"
echo "Converting Done!"
#echo "You can safely remove working folder at: '$JB5Backup'"
echo -e "Your cPanel backup:\n$DestDir/cpmove-$AccountName.tar.gz"

