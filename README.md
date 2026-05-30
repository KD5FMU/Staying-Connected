# ASL3 Check Connection Script

This is a simple AllStarLink Version 3 helper script for Debian 12 that checks to see if your node is connected to another node.

If your node is not connected to the node you choose, the script will automatically send the connect command and reconnect it.

This can be useful if you want your AllStarLink node to stay connected to a hub, repeater, private node, or another AllStarLink node.

## What This Installs

This installer will install the needed files to:

```bash
/etc/asterisk/local/
```

The main files are:

```bash
/etc/asterisk/local/check-connection.sh
/etc/asterisk/local/check_connection.conf
```

The script reads the settings from:

```bash
/etc/asterisk/local/check_connection.conf
```

The script can also be run from cron so it can check the connection automatically.

## What It Does

This script checks your AllStarLink node and looks to see if it is connected to the node number you have listed in the config file.

If the node is already connected, it does nothing.

If the node is not connected, it sends the AllStarLink connect command and attempts to reconnect.

For example, if you want your node to stay connected to node `57841`, the script can automatically send:

```bash
*357841
```

That means the script is using the normal AllStarLink connect command.

## Important Note

This script is intended for AllStarLink Version 3 running on Debian.

It is designed to be simple and easy to understand.

Please read the script before using it. Linux will do exactly what you tell it to do, even if you had more coffee than sleep.

## Install Instructions

First we download the installer script file:

```bash
wget https://raw.githubusercontent.com/KD5FMU/YOUR-REPOSITORY-NAME/refs/heads/main/install.sh
```

Then make it executable:

```bash
sudo chmod +x install.sh
```

Then we can execute the installer script:

```bash
sudo ./install.sh
```

Once the installer is finished, you will need to edit the config file.

```bash
sudo nano /etc/asterisk/local/check_connection.conf
```

## Config File

Inside the config file you will need to set your local node number and the node number you want to stay connected to.

Example:

```bash
LOCAL_NODE="577881"
TARGET_NODE="57841"
```

Change these numbers to match your own AllStarLink setup.

Example:

```bash
LOCAL_NODE="YOUR_NODE_NUMBER"
TARGET_NODE="NODE_TO_STAY_CONNECTED_TO"
```

Save the file.

In nano:

```bash
CTRL + O
ENTER
CTRL + X
```

## Make Sure The Script Is Executable

The installer should already do this for you, but if you need to do it manually, run:

```bash
sudo chmod +x /etc/asterisk/local/check-connection.sh
```

## Test The Script Manually

You can test the script by running:

```bash
sudo /etc/asterisk/local/check-connection.sh
```

If your node is already connected to the target node, the script should report that it is already connected.

If your node is not connected, it should attempt to reconnect.

## Test It In A Cron-Like Environment

Cron does not always use the same PATH that your normal terminal uses.

To test it more like cron will run it, use:

```bash
sudo env -i PATH="/usr/bin:/bin" /etc/asterisk/local/check-connection.sh
```

If it runs correctly there, it should also work from cron.

## Add It To Cron

To have the script check the connection automatically, edit root's crontab:

```bash
sudo crontab -e
```

Then add a line like this:

```bash
*/5 * * * * /etc/asterisk/local/check-connection.sh >/dev/null 2>&1
```

This will run the script every 5 minutes.

If you want it to check every minute, use this instead:

```bash
* * * * * /etc/asterisk/local/check-connection.sh >/dev/null 2>&1
```

## View The Logs

The script uses the system logger with the tag:

```bash
asl3-check-connection
```

You can view the logs with:

```bash
sudo journalctl -t asl3-check-connection
```

To watch the logs live:

```bash
sudo journalctl -t asl3-check-connection -f
```

## Common Problems

### Permission Denied

If you see something like this:

```bash
Permission denied
```

Run:

```bash
sudo chmod +x /etc/asterisk/local/check-connection.sh
```

Then test it again:

```bash
sudo /etc/asterisk/local/check-connection.sh
```

### Asterisk Command Not Found

If you see something like this:

```bash
ERROR: asterisk command not found.
```

This usually means the script could not find the `asterisk` command when running from cron.

This script should use the full path to Asterisk.

You can check where Asterisk is installed by running:

```bash
command -v asterisk
```

On many ASL3 systems, it should be:

```bash
/usr/sbin/asterisk
```

## Uninstall Instructions

If you want to remove this script from your system, first remove the cron entry.

Open root's crontab:

```bash
sudo crontab -e
```

Remove the line that looks like this:

```bash
*/5 * * * * /etc/asterisk/local/check-connection.sh >/dev/null 2>&1
```

Then remove the installed script and config file:

```bash
sudo rm -f /etc/asterisk/local/check-connection.sh
sudo rm -f /etc/asterisk/local/check_connection.conf
```

That will remove the check connection script from your system.

## Manual Cleanup

After uninstalling, you can check to make sure the files are gone:

```bash
ls -l /etc/asterisk/local/check-connection.sh
ls -l /etc/asterisk/local/check_connection.conf
```

If the files are removed, you may see:

```bash
No such file or directory
```

That is okay. That means they are gone.

## License

This project is licensed under the MIT License.

By submitting a contribution to this repository, you agree that your contribution is licensed under the same MIT License.

## Contributing

Contributions are welcome, but please only submit code that you wrote yourself or code that you have the legal right to contribute.

By submitting a pull request, patch, issue comment containing code, or other contribution, you agree that your contribution is licensed under the same license as this project.

Please do not submit copied code from another project unless the license is compatible and all required copyright notices are preserved.

## Final Note

I hope this helps make your AllStarLink node a little more dependable.

73!


