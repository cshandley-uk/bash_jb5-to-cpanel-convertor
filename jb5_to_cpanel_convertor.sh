#!/bin/bash
#
# Created by TheLazyAdmin, https://thelazyadmin.blog
#
# ** USE AT YOUR OWN RISK ** 
#

function print_help {
  echo "
   Example for manual usage :

       jb5_to_cpanel_convertor.sh {JETBACKUP5_BACKUP} {DESTINATION_ARCHIVE}

        {JETBACKUP5_BACKUP} JetBackup file location
        {DESTINATION_ARCHIVE} Where to put the cPanel gereated backup

        jb5_to_cpanel_convertor.sh /usr/local/jetapps/usr/jetbackup5/downloads/download_jb5user_1663238955_28117.tar.gz /root/cpanel_structure

   Example for auto usage :

        jb5_to_cpanel_convertor.sh {ACCOUNT} {DESTINATION_ARCHIVE} --fetch

        {ACCOUNT} cPanel Account name
        {DESTINATION_ARCHIVE} Where to put the cPanel generated backup
        --fetch Auto download the *LAST* backup for the specified account

        jb5_to_cpanel_convertor.sh username /root/cpanel_structure --fetch
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

function create_dir() {
    DIRECTORY_PATH=$1
    mkdir $DIRECTORY_PATH >/dev/null 2>&1
    CODE=$?
    [[ $CODE -gt 0 ]] && message "Error: The directory $DIRECTORY_PATH already exist delete the directory to continue" 1
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
[[ $DES_PATH == "--fetch" ]] && message "Error :: Destination path not provided"

if [[ $FETCH_DOWNLOAD == "--fetch" ]]; then

  ACCOUNT_NAME=$1
  id $ACCOUNT_NAME > /dev/null 2>&1
  CODE=$?
  [[ $CODE != 0 ]] && message "Provided user $ACCOUNT_NAME not found" 1

  JETBACKUP_ACCOUNT_NAME=$ACCOUNT_NAME

  echo "Fetching JetBackup download for: $JETBACKUP_ACCOUNT_NAME"

  JETBACKUP_ACCOUNT_ID=$( /usr/bin/jetbackup5api -F listBackupForAccounts -D "type=1&contains=511" | grep -w "$JETBACKUP_ACCOUNT_NAME" -B1 | grep 'account_id' | awk {'print $2'} )
  [[ -z "$JETBACKUP_ACCOUNT_ID" ]] && message "No full backups found for this account" 1

  echo "Retrieved Account ID: $JETBACKUP_ACCOUNT_ID"
  JETBACKUP_BACKUP_ID=$( /usr/bin/jetbackup5api -F listBackupForTypeName -D "type=1&contains=511&account_id=$JETBACKUP_ACCOUNT_ID&name=$JETBACKUP_ACCOUNT_NAME" | grep 'parent_id' -B1 | grep -w -m1 '_id:' | awk {'print $2'} )
  [[ -z "$JETBACKUP_BACKUP_ID" ]] && message "Something went wrong, couldn't retrieve an account ID" 1

  echo "Retrieved Backup ID: $JETBACKUP_BACKUP_ID"
  JETBACKUP_SNAP_ID=$( /usr/bin/jetbackup5api -F getBackupItem -D "_id=$JETBACKUP_BACKUP_ID" | grep 'parent_id' | awk {'print $2'} )
  [[ -z "$JETBACKUP_SNAP_ID" ]] && message "Something went wrong, couldn't retrieve an snap ID" 1

  echo "Retrieved Snap ID: $JETBACKUP_SNAP_ID"
  JETBACKUP_QUEUE_ID=$( /usr/bin/jetbackup5api -F addQueueItems -D "type=4&snapshot_id=$JETBACKUP_SNAP_ID" | grep '_id:' | awk {'print $2'} )
  [[ -z "$JETBACKUP_SNAP_ID" ]] && message "Something went wrong, couldn't add to queue" 1

  echo "Backup queued for download, queue ID: $JETBACKUP_SNAP_ID"
  echo "Waiting for download to finish (you can also monitor from JetBackup GUI -> Queue)"
  echo "It's time to get a coffee :)"

  RETRY=1
  JET_BREAK=0

  while [ $RETRY -ne 0 ]
    do
        sleep 1
        JETBACKUP_QUEUE_STATUS=$( /usr/bin/jetbackup5api -F getQueueGroup -D "_id=$JETBACKUP_QUEUE_ID" | grep 'status:' | awk {'print $2'} )

          case $JETBACKUP_QUEUE_STATUS in
            30)
              JETBACKUP_QUEUE_EXEC=$( /usr/bin/jetbackup5api -F getQueueGroup -D "_id=$JETBACKUP_QUEUE_ID" | grep 'execution_time:' | awk {'print $2'} )
              echo "Executed time: $JETBACKUP_QUEUE_EXEC"
              RETRY=1
              ;;

            100)
              echo "Download finished successfully!"
              RETRY=0
              JET_BREAK=0
              ;;
            102)
              echo "ERROR: Download Failed!"
              RETRY=0
              JET_BREAK=1
              ;;
            *)
              RETRY=1
              #JET_BREAK=1
              ;;
          esac
    done

  JETBACKUP_LOG_FILE=$( /usr/bin/jetbackup5api -F getQueueGroup -D "_id=$JETBACKUP_QUEUE_ID" | grep 'log_file:' | awk {'print $2'} )

  [[ $JET_BREAK -ne 0 ]]  && message "Error occurred while trying to fetch download, log file: $JETBACKUP_LOG_FILE" 1
  BACKUP_PATH=$( cat "$JETBACKUP_LOG_FILE" | grep 'Download location' | awk {'print $NF'} )
  BACKUP_PATH="${BACKUP_PATH%%[[:cntrl:]]}"

else
  BACKUP_PATH=$(echo $FILE_PATH)
  ACCOUNT_NAME=$(echo $FILE_PATH |  grep -oP '(?<=download_)([^_]+)')
  ! [[ -f $BACKUP_PATH ]] && message "Invalid file provided"
fi

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
   else rsync -ar "$JB5_BACKUP/homedir" "$CPANEL_DIRECTORY"
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
