#! /bin/bash

# ==INFO==
# I tried pretty much every audio host out there, and running headless etc
# before finding audio tweaks that sent me from jackd collapsing to x-run free

# This script switches on those tweaks;  and switches them back off when done

# If using audio_mode from within X, holding eject key can reboot the audio
# (for emergency recovery during a performance!)

# When running headless.  X is shutdown for the duration (if it was active)

# NOTE: jumping back to the tty as X reloads can make it unhappy
# if this happens, try typing: sudo lightdm service force-reload


# ==CONFIG==
# Do our apps need the network?
NETWORK=false

# path to the display manager
DM=/usr/sbin/lightdm

# name of systemd service used to startup/shutdown X
DMSERVICE=lightdm

# stdout is hidden.  If you run this script from a terminal and desire to see
# stdout + random messages, then change VERBOSE to true
VERBOSE=false

# Edit setup_apps() to run the audio apps you need
# It must halt until you want the audio mode to end

setup_apps__example() {
	# open jack/apps.  ladish is one way to do it
	ladish_control sload my_example_studio
	ladish_control sstart
	# this is the only required part of the setup:
	# we need to halt this script until the audio mode should end
	xmessage 'Audio mode now active...
Run whatever apps you like,  then close me to exit' \
					 -buttons exit -default exit
	# tidy up
	ladish_control sstop
	ladish_control sunload
	ladish_control exit; }

# Edit setup_interfaces()
# if you'll only use one interface, then this is fine:

setup_interfaces__example() { setup_apps; }

# When audio mode is active the computer wont sleep or dim the screen
# but this is done for xfce and headless.  If you computer setup differs,
# you might want to edit this and maybe elsewhere...



# ==EDIT THESE==

setup_apps() {
	# this is my actual setup

	#jackd -P80 --port-max 128 $INTERFACE --midi none &
	#ecasound -c -Md rawmidi,/dev/snd/midiC1D0 -i jack,system -o jack,system -ea:230 -km:1,0,300,7,1 -E t >&2
	#carla /home/samuel/bin/carla.carxp
	
	jackd -P80 --temporary --port-max 128 $INTERFACE --midi raw &
	NoGUI='--nogui'; [ "$X_USING" ] && NoGUI=''
	guitarix $NoGUI --no-convolver-overload &
	# try to restore midi/jack connections
	(until [ "`pgrep guitarix`" ]; do sleep 2; done; sleep 2
		aj-snapshot -r /home/samuel/bin/guitarix.xml) &

	# Reboot audio apps (for quick recovery when live!)
	# in X: holding eject key reboots audio

	# out of X, eject key isnt going to work
	# so 'q' quits;  'r' reboots
	
	# pass it the pids of any apps to kill so they reboot nicely
	# but ladish may not like you, so alternatively
	# replace this line with something like "wait `pgrep guitarix`"
	setup_reboot "`pgrep guitarix`"; }

setup_interfaces() {
	# interface specific tweaks

	# select the external audio interface if its plugged in
	if lsusb | grep "Line6"; then
		# stop resource conflict with internal audio interface
		sudo modprobe -r snd_hda_intel
		# prioritize audio over usb3
		sudo chrt -f -p 88 `irq_pid usb3`

		INTERFACE='-d alsa -d hw:VX --softmode -r48000 -n3 -p64'
		setup_apps
		
		# begin exiting audio mode
		sudo modprobe -a snd_hda_intel
		sudo chrt -f -p 50 `irq_pid usb3`
	else
		sudo chrt -f -p 88 `irq_pid snd`
		INTERFACE='-d alsa -d hw:0 --softmode -r48000 -n2 -p128'
		setup_apps
		sudo chrt -f -p 50 `irq_pid snd`
	fi }






# ==ACTUAL SCRIPT==
# If the script isnt running: switch on VERBOSE=true,
# run from a terminal, and edit the below...

setup_reboot() {
	REBOOT=''
	if [ "$X_USING" ]; then
		(# make sure eject key is not being pressed
			until [ `xinput --query-state 11 | grep '\[169\]=up'` ]; do sleep 3; done
			(sleep 2; echo \
'--------------------
  quit app: exit
  hold ESC: reboot
--------------------' >&2) &
			# pause this sub-shell until eject key is held (for ~3 seconds)
			until [ `xinput --query-state 11 | grep '\[169\]=down'` ]; do sleep 3; done
			# reboot our audio apps
			safe_kill $1; xmessage 'Rebooting audio...' -buttons cancel) &
		SPID=$!
		wait $1
		safe_kill $SPID
	else
		while [ "$REBOOT" = '' ]; do
			(sleep 2; echo \
'-------------
  q: exit
  r: reboot
-------------' >&2) &
			read -n1 REBOOT
			if [ "$REBOOT" = 'r' ]; then safe_kill $1
			elif [ "$REBOOT" != 'q' ]; then REBOOT=''; fi
		done
	fi

	clearup_apps
	
	if [ "`pgrep -f 'xmessage Rebooting audio...'`" -o "$REBOOT" = 'r' ]; then
		log 'Rebooting audio apps...'
		safe_kill `pgrep -f 'xmessage Rebooting audio...'`
		# thankyou pulse for fixing our connection :)
		# you may want to uncomment these dependng on why your audio is falling over
		#pulseaudio --start
		#pulseaudio --kill
		setup_apps; fi }

clearup_apps() {
	# make sure we dont re-ask for the password
	echo $PASS | sudo -S printf '' 2>/dev/null
	
	# jack probably isnt running at this point, but lets encourage it anyway
	jack_control exit 2>/dev/null; a2j_control exit 2>/dev/null &
	safe_kill `user_pid '(\/usr\/bin\/)?jackd'`; }

control_services() {
	# services to take down while audio is running
	sudo service anacron $1 &
	sudo service cron $1 &
	sudo service network-manager $1 &
	sudo service ntp $1 &
	#sudo service wpa_supplicant $1 &
	[ "$NETWORK" = false ] && sudo service networking $1
	sudo systemctl $1 bluetooth
	sudo systemctl $1 colord
	sudo systemctl $1 accounts-daemon
	sudo systemctl $1 cpufreqd
	sudo systemctl $1 cpufrequtils
	sudo systemctl $1 loadcpufreq
	
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
	if [ "$X_USING" ]; then
		if [ "`ps -axo comm | grep '^xfce'`" ]; then
			# this only works for xfce
			xfconf-query -c xfce4-power-manager \
									 -p /xfce4-power-manager/presentation-mode -s $1
		else
			# a generic jiggle solution
			# assumes computer will stay awake longer than a minute
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
	# these programs cause xruns when they get too excited
	# emacs doesn't, but I leave it on during audio mode
	Processes="
		`pgrep -f '/usr/bin/emacs'`
		`user_pid '\/usr\/share\/brave\/brave'`
		`pgrep -f 'evince'`
		`pgrep -f 'xfwm4 --'`
		`user_pid xfce4`
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
	ID=`cat /proc/interrupts | sed -rn "s/ *\w*: +\w+ +\w+ +\w+-\w+ +([0-9]+)-\w+ +.*$1.*/\1/p"`
	# sometimes pids share an irq id, so extract distinguishing text too
	TEXT=`cat /proc/interrupts | sed -rn "s/ *\w*: +\w+ +\w+ +\w+-\w+ +[0-9]+-\w+ +(.*)$1(.*).*/\1$1\2/p" | sed -r "s/(.*, )*([^ :]*):?$1:?([^ :]*)(, .*)*/\2|$1|\3/"`
	# remove empty strings
	TEXT=`echo "$TEXT" | sed -r 's/\|?([^ ]+(\|[^ ]+)*)\|?/(\1)/'`
	# if name is ambiguous, then do each one
	paste <(echo "$ID") <(echo "$TEXT") --delimiters '-' | \
	while read LINE; do
		ps -eo pid,comm | sed -rn "s/ *([0-9]+) irq\/$LINE.*/\1/p"
	done }

user_pid() {
	ps -xo pid,args -U `id -u` | sed -rn "s/ ?([0-9]+).*[^]]$1.*/\1/p"; }

safe_kill() {
	# give pids 15secs to quit.  If they take longer then zap them
	(sleep 15; kill -0 $1 2>/dev/null && kill -9 $1) &
	kill $1 2>/dev/null
	# hide notifications
	wait $1 2>/dev/null; }

log() { logger $1; echo $1 >&2; }
	
audio_mode() {		
	# stdout to /dev/null
	[ "$VERBOSE" = false ] && exec 1>/dev/null
	
	# safely get root
	if [ -f ~/bin/authinfo.py -a -f ~/.authinfo.gpg ]; then
		PASS=`cd ~/bin; python -c 'import authinfo; print authinfo.get_password("jbook", "sudo", "root")'`
	else PASS=`ssh-askpass`; fi

	log 'Entering audio mode...'

	# is X running
	X_RUNNING=`ps -axo args | egrep "^$DM"`	
	# run through parent processes to see if the dm is one of them
	# (if its not we can quit X)
	PID=$$
	while true; do
		PID=`ps -ho %P -p $PID`
		[ $PID = 1 ] && break
		# i am the fire starter
		X_USING=`ps -ho args -p $PID | grep "$DM"`
		[ "$X_USING" ] && break
	done

	# use PASS so we don't need to ask for the password again when exiting
	echo $PASS | sudo -S printf '' 2>/dev/null
	
	# configure for audio performance
	echo -n performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
	echo
	SWAP=`cat /proc/sys/vm/swappiness`
	sudo sysctl -w vm.swappiness=5 2>/dev/null
	MODULES='r8169 ath9k uvcvideo videodev lp ppdev pata_acpi
		brcmsmac brcmutil b43 bcma btusb'
	sudo modprobe -r $MODULES
	sudo modprobe snd-hrtimer
	# increase the rtc timer frequency
	RTC_FREQ=`cat /sys/class/rtc/rtc0/max_user_freq`
	echo -n 3072 | sudo tee /sys/class/rtc/rtc0/max_user_freq
	be_nice 15
	keep_awake true
	control_services stop
	pulseaudio --kill 2>/dev/null
	/etc/init.d/rtirq start
	sudo chrt -f -p 90 `irq_pid rtc0`

	setup_interfaces
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