# bash_jb5-to-cpanel-convertor
This Bash script converts a supplied JetBackup 5 backup file to a cPanel-compatible backup (which can then be restored by WHM, etc).

I expect the script to be used when you want to migrate to another cPanel host, but the old host only provides JetBackup 5 backups, and the new host doesn't use JetBackup 5.  The script currently assumes root access to the new hosting (particularly for the temporary folder), although that could easily be fixed.

I hope that other people will improve the script.  I would be happy to receive pull requests.

# Warning
While the script seems to work pretty well in my limited tests, the created cPanel backup could easily be missing some (probably less common) things that I don't use, and there might be other problems.  So please thoroughly compare any restored account against the original & test that everything works the same.  I highly recommend keeping the original JetBackup 5 backup files, just in case you later discover that something is missing or incorrect.

This script is provided under the MIT License (see the source code).  Please take special note that:

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

** USE AT YOUR OWN RISK **

# Requirements
The "jq" command must be installed: 
https://jqlang.github.io/jq/

If you use a RedHat/CentOS-based system, then "jq" is available from the EPEL repository.

The script also uses the "gunzip" & "tar" commands, but these are typically already installed on Linux.

# Usage
`jb5_to_cpanel_convertor.sh JETBACKUP5_BACKUP [DESTINATION_FOLDER]`

JETBACKUP5_BACKUP  = Source JetBackup file

DESTINATION_FOLDER = Optional destination folder for cPanel backup, defaults to /home/

e.g. 
`jb5_to_cpanel_convertor.sh /home/download_jb5user_1663238955_28117.tar.gz`

# History
The script is heavily based upon the one kindly provided by TheLazyAdmin here:
https://thelazyadmin.blog/convert-jetbackup-to-cpanel

Under the MIT license:
https://thelazyadmin.blog/convert-jetbackup-to-cpanel#comment-3240

I ran into several issues with the created cPanel backups, which I have since fixed:
* It failed to restore addon, alias & sub domains.
* It failed to restore mailboxes.
* It failed to restore SSL certificates (at least on the hosting I was using).
* It didn’t restore DNS zones.

In addition to that I made a number of other changes to the code, including:
* I removed the `--fetch` option which caused the local server to generate a new JetBackup 5 backup, as this is only useful if you have root access to the source server - in which case you could just re-enable cPanel’s built-in backup functionality anyway.  The --fetch code was just extra complexity that I didn’t need when trying to understand & improve the script, and I wouldn't have been unable to test it anyway.
* I made it allocate a proper /tmp folder for storing temporary files (e.g. unpacked archive), which is always deleted - rather than leaving a randomly named folder in the destination that the user must manually delete.
* Quoted almost all variables, so spaces in filenames won’t break the script or cause incorrect behaviour.
* Quoted all $(…) embedded code, so that unexpected spaces in the output won’t break the script or cause incorrect behaviour.

And before I did any of that, I changed the style of the code to be easier for me to follow & edit, including:
* Converted indenting from spaces to tabs.
* Changed variable names from being all UPPERCASE to lowercase.
* Changed procedure & variable names from using underscores to separate words to instead use capitalisation (so called PascalCase).
