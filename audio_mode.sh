#! /bin/bash

## ==INFO==
# I tried pretty much every audio host out there, and running headless etc
# before finding audio tweaks that sent me from constant noise to x-run free

# This script switches on those tweaks;  and switches them back off when done

# If using audio_mode from within X:  holding eject key can reboot the audio

# When running headless:  X is shutdown for the duration (if it was active)



## ==CONFIG==
# do our apps need the network?
NETWORK=false

# name of systemd service used to startup/shutdown X
DMSERVICE=lightdm

# let me sleep?
SLEEP=false

# key to reboot audio under X
# on my computer 169=ejectkey.  To change the key, run
# 'xev', and look for keycode NNN
REBOOTKEY=169

# stdout is hidden.  If you run this script from a terminal and desire to see
# stdout + random messages, then change VERBOSE to true
VERBOSE=false


## here are the setup functions to run when in audio_mode
# simply write a setup_NAME() function to add a new one :)
# then run it with './audio_mode.sh NAME'

setup_default() {
	message 'Audio mode active...
Run whatever apps you like, then close me to exit' -buttons exit -default exit; }


LADISH_STUDIO="${@:2}"
setup_ladish() {
	# ladish is your friend
	ladish_control sload "$LADISH_STUDIO"
	ladish_control sstart
	# halt the script here until the audio mode should end
	message 'Audio mode now active... Close me to exit' -buttons exit -default exit
	# tidy up
	ladish_control sstop
	ladish_control sunload
	ladish_control exit; }


setup_guitarix() {
	# a straightforward example of running headless and handle_reboot
	# jack can be run from guitarix
	
	# X_USING tests if we are in X
	local NoGUI='--nogui'; [ "$X_USING" ] && NoGUI=''
	guitarix $NoGUI --no-convolver-overload &

	## reboot audio apps (for quick recovery when live!)
	# in X: holding eject key reboots audio

	# out of X, eject key isnt going to work
	# so 'q' quits;  'r' reboots
	
	# pass it the pids of any apps to kill so they reboot nicely
	# but ladish may not like you for it
	handle_reboot "`pgrep guitarix`"; }


SCRIPT_PATH="${@:2}"
setup_script() {
	# run a script when audio mode starts

	## script could be something like:
	# jackd settings... &
	# /path/to/my/app &
	# /path/to/my/other/app2 &
	# if [ "$X_USING" ]; then $(xmessage hello gui &); fi
	# handle_reboot "`pgrep app` `pgrep app2`"

	# then run it with ./audio_mode.sh script /path/to/my/script
	if [ ! -f "$SCRIPT_PATH" ]; then
		log "script $SCRIPT_PATH could not be found"
		exit
	fi
	source $SCRIPT_PATH; }


setup_samuel() {
	# this is my actual setup
	
	# select the external audio interface if its plugged in
	local LINE6=`lsusb | grep "Line6"`
	if [ "$LINE6" ]; then
		# do some interface specific tweaks
		INTERFACE='-d alsa -d hw:VX --softmode -r48000 -n3 -p64'
		# stop resource conflict with internal audio interface
		sudo modprobe -r snd_hda_intel
		# prioritize audio over usb3
		sudo chrt -f -p 88 `irq_pid usb3`
	else
		INTERFACE='-d alsa -d hw:0 --softmode -r48000 -n2 -p128'
		sudo chrt -f -p 88 `irq_pid snd`
	fi

	# switch the SETUP_CMD command so handle_reboot doesnt
	# re-run this interface initialization aswell
	SETUP_CMD=setup_samuel_reboot
	$SETUP_CMD
	
	# begin exiting audio mode
	# reset the interface settings
	if [ "$LINE6" ]; then
		sudo modprobe -a snd_hda_intel
		sudo chrt -f -p 50 `irq_pid usb3`
	else
		sudo chrt -f -p 50 `irq_pid snd`
	fi }


setup_samuel_reboot() {
	# now the interface is done, we run some apps
	
	#jackd -P80 --port-max 128 $INTERFACE --midi none &
	#ecasound -c -Md rawmidi,/dev/snd/midiC1D0 -i jack,system -o jack,system -ea:230 -km:1,0,300,7,1 -E t >&2
	#carla /home/samuel/bin/carla.carxp

	jackd -P80 --temporary --port-max 128 $INTERFACE --midi raw &
	local NoGUI='--nogui'; [ "$X_USING" ] && NoGUI=''
	guitarix $NoGUI --no-convolver-overload &
	# try to restore midi/jack connections
	(until [ "`pgrep guitarix`" ]; do sleep 2; done; sleep 2
		aj-snapshot -r /home/samuel/bin/guitarix.xml) &
	handle_reboot "`pgrep guitarix`"; }






## ==ACTUAL SCRIPT==
# If there are problems running the script:
# switch on VERBOSE=true, run from a terminal, and edit the below...

log() { logger "$@"; echo "$@" >&2; notify-send "$@"; }

message() {
	## script-blocking dialog boxes when in and out of X
	if [ "$X_USING" ]; then xmessage "$1"
	else printf -- \
"-------------
  $1
  press any key to continue
-------------" -- >&2
			 read -n1; echo >&2; fi }


## which function will run after we've entered audio mode
# so running this script with './audio_mode.sh ladish studio_x'
# will enter audio mode, then run setup_ladish
SETUP_CMD=setup_$1
[ ! "$1" ] && SETUP_CMD=setup_default
if ! declare -f "$SETUP_CMD" >/dev/null; then
	log "$SETUP_CMD not found. Cannot start audio mode";
	exit
fi


handle_reboot() {
	## handle quick rebooting of the audio setup
	# -- reboot kills jack + any pids passed and re-runs $SETUP_CMD
	
	local REBOOT=''
	if [ "$X_USING" ]; then
		(# make sure eject key is not being pressed
			until [ `xinput --query-state 11 | grep "\[$REBOOTKEY\]=up"` ]; do sleep 3; done
			(sleep 2; echo \
'--------------------
  quit app: exit
  hold ESC: reboot
--------------------' >&2) &
			# pause this sub-shell until eject key is held (for ~3 seconds)
			until [ `xinput --query-state 11 | grep "\[$REBOOTKEY\]=down"` ]; do sleep 3; done
			# reboot our audio apps
			safe_kill $1; xmessage 'Rebooting audio...' -buttons cancel) &
		local SPID=$!
		wait $1
		safe_kill $SPID
	else
		while [ "$REBOOT" = '' ]; do
			(sleep 2; printf -- \
'-------------
  q: exit
  r: reboot
-------------' -- >&2) &
			read -n1 REBOOT; echo >&2
			if [ "$REBOOT" = 'r' ]; then safe_kill $1
			elif [ "$REBOOT" != 'q' ]; then REBOOT=''; fi
		done
	fi

	clearup_apps
	
	if [ "`pgrep -f 'xmessage Rebooting audio...'`" -o "$REBOOT" = 'r' ]; then
		log 'Rebooting audio apps...'
		safe_kill `pgrep -f 'xmessage Rebooting audio...'`
		## thankyou pulse for fixing our connection :)
		# you may want to uncomment these dependng on why your audio is falling over
		#pulseaudio --start
		#pulseaudio --kill
		$SETUP_CMD; fi }


clearup_apps() {
	## a generic tidy-up function
	# make sure we dont re-ask for the password
	echo $PASS | sudo -S printf '' 2>/dev/null
	
	# jack probably isnt running at this point, but lets encourage it anyway
	#jack_control exit 2>/dev/null;
	a2j_control exit 2>/dev/null &
	safe_kill `user_pid '(\/usr\/bin\/)?jackd'`; }


control_services() {
	## services to take down while audio is running
	sudo service anacron $1 &
	sudo service cron $1 &
	sudo service network-manager $1 &
	sudo service ntp $1 &
	#sudo service wpa_supplicant $1 &
	[ "$NETWORK" = false ] && sudo service networking $1 &
	sudo systemctl $1 bluetooth &
	sudo systemctl $1 colord &
	sudo systemctl $1 accounts-daemon &
	sudo systemctl $1 cpufreqd &
	sudo systemctl $1 cpufrequtils &
	sudo systemctl $1 loadcpufreq &
	
	# ModemManager
	
	sudo systemctl $1 cups.path
	sudo systemctl $1 acpid.path
	sudo systemctl $1 acpid.socket
	sudo systemctl $1 avahi-daemon.socket 2>/dev/null
	sudo systemctl $1 snapd.socket
	if [ $1 = 'stop' ]; then
		sudo service cups $1 &
		sudo service acpid $1 &
		sudo service avahi-daemon $1 2>/dev/null &
		sudo systemctl $1 snapd &
	fi

	# if we're not using X, then save ourselves from its eye candy
	if [ ! "$X_USING" ]; then
		[ "$X_RUNNING" ] && sudo service $DMSERVICE $1
		export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
	fi

	# can we switch on/off dbus?
	#sudo service dbus $1
	if [ "$1" = 'stop' ]; then
		:
		#sudo killall console-kit-daemon
		#sudo killall polkitd
		#killall dbus-daemon
		#killall dbus-launch
	fi }


keep_awake() {
	# switch into presentation mode (i.e. dont sleep)
	[ "$SLEEP" = false ] && if [ "$X_USING" ]; then
		if [ "`ps -axo comm | grep '^xfce'`" ]; then
			# this only works for xfce
			xfconf-query -c xfce4-power-manager \
									 -p /xfce4-power-manager/presentation-mode -s $1
		else
			## a generic jiggle solution
			# assumes computer can stay awake longer than a minute
			if [ "$1" = true ]; then
				xset s off -dpms
				(while true; do
					 xdotool mousemove_relative --sync 1 1
					 xdotool mousemove_relative --sync -- -1 -1
					 sleep 60
				 done) &
				JPID=$!
			else xset s default +dpms; safe_kill $JPID; fi
		fi
	else
		# when running from a terminal (out of X)
		if [ "$1" = true ]; then setterm -blank 0 -powerdown 0 -powersave off
		else setterm -default; fi
	fi }


be_nice() {
	## these programs cause xruns when they get too excited
	# emacs doesn't, but I leave it on during audio mode
	local Processes="
		`pgrep -f '/usr/bin/emacs'`
		`user_pid '\/usr\/share\/brave\/brave'`
		`pgrep -f 'evince'`
		`pgrep -f 'xfwm4 --'`
		`user_pid .*[x]fce4`
		`pgrep -f 'xfsettingsd --'`
		`pgrep -f '/usr/lib/xorg/Xorg'`
		`pgrep -f '/usr/lib/udisks2/udisksd'`
		`pgrep -f '/usr/lib/upower/upowerd'`
		`pgrep -f '/sbin/init splash'`
		`pgrep -f 'syndaemon -'`
		`pgrep -f 'upstart-dbus-bridge'`
		`pgrep -f 'dbus-daemon'`"
	sudo renice -n $1 $Processes; }


irq_pid() {
	# get irqs, then extract pid for a given name
	local ID=`cat /proc/interrupts | sed -rn "s/ *\w*: +\w+ +\w+ +\w+-\w+ +([0-9]+)-\w+ +.*$1.*/\1/p"`
	# sometimes pids share an irq id, so extract distinguishing text too
	local TEXT=`cat /proc/interrupts | sed -rn "s/ *\w*: +\w+ +\w+ +\w+-\w+ +[0-9]+-\w+ +(.*)$1(.*).*/\1$1\2/p" | sed -r "s/(.*, )*([^ :]*):?$1:?([^ :]*)(, .*)*/\2|$1|\3/"`
	# remove empty strings
	TEXT=`echo "$TEXT" | sed -r 's/\|?([^ ]+(\|[^ ]+)*)\|?/(\1)/'`
	# if name is ambiguous, then do each one
	paste <(echo "$ID") <(echo "$TEXT") --delimiters '-' | \
	while read LINE; do
		ps -eo pid,comm | sed -rn "s/ *([0-9]+) irq\/$LINE.*/\1/p"
	done }


user_pid() { ps -xo pid,args -U `id -u` | sed -rn "s/^ *([0-9]+) $1.*$/\1/p"; }


safe_kill() {
	# dont waste time if we've got nothing to do
	[ ! "$1" ] && return
	# give pids 15secs to quit.  If they take longer then zap them
	(sleep 15; kill -0 $1 2>/dev/null && kill -9 $1) &
	kill $1 2>/dev/null
	# hide notifications
	wait $1 2>/dev/null; }


audio_mode() {
	# stdout to /dev/null
	[ "$VERBOSE" = false ] && exec 1>/dev/null
	
	# safely get root
	if [ -f ~/bin/authinfo.py -a -f ~/.authinfo.gpg ]; then
		PASS=`cd ~/bin; python -c 'import authinfo; print authinfo.get_password("jbook", "sudo", "root")'`
	else PASS=`ssh-askpass`; fi

	## use PASS so we don't need to ask for the password again when exiting
	sudo -k # make sure $PASS is right
	if ! echo "$PASS" | sudo -S printf '' 2>/dev/null; then
		log 'Password was incorrect'; exit; fi
	
	log 'Entering audio mode...'

	## initialize X_RUNNING and X_USING
	# [ "$X_RUNNING" ] true when X is running
	# [ "$X_USING" ] true when this script is run from X
	X_RUNNING=`systemctl status $DMSERVICE | head -5 | grep '^ *Active: active'`
	# run through parent processes to see if the dm is one of them
	# (if its not we can quit X)
	local DMPID=`systemctl status $DMSERVICE | head -5 | sed -rn 's/^ *(Main)? *PID: ([0-9]+).*/\2/p'`
	local PID=$$
	while true; do
		PID=`ps -ho %P -p $PID`
		[ $PID = 1 ] && break
		if [ $DMPID = $PID ]; then X_USING=true; break; fi
	done

		
	# configure for audio performance
	echo -n performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
	echo
	local SWAP=`cat /proc/sys/vm/swappiness`
	sudo sysctl -w vm.swappiness=5 2>/dev/null
	local MODULES='r8169 ath9k uvcvideo videodev lp ppdev pata_acpi
		brcmsmac brcmutil b43 bcma btusb'
	sudo modprobe -r $MODULES
	sudo modprobe snd-hrtimer
	# increase the rtc timer frequency
	local RTC_FREQ=`cat /sys/class/rtc/rtc0/max_user_freq`
	echo -n 3072 | sudo tee /sys/class/rtc/rtc0/max_user_freq
	be_nice 15
	keep_awake true
	control_services stop
	pulseaudio --kill 2>/dev/null
	/etc/init.d/rtirq start
	sudo chrt -f -p 90 `irq_pid rtc0`

	$SETUP_CMD
	clearup_apps
	
	log 'Restoring non-audio setup...'

	# reset computer configuration
	echo -n ondemand | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
	echo
	sudo sysctl -w vm.swappiness=$SWAP
	sudo modprobe -a $MODULES
	sudo modprobe -r snd-hrtimer
	echo -n $RTC_FREQ | sudo tee /sys/class/rtc/rtc0/max_user_freq
	be_nice 0
	control_services start
	keep_awake false
	#pulseaudio --start &
	sudo chrt -f -p 50 `irq_pid rtc0`
	/etc/init.d/rtirq stop

	log 'Exited audio mode'; }


audio_mode