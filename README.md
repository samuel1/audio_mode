# audio_mode
One click audio configuration for linux


## About
I tried so many things, like running headless etc.  Before finding audio tweaks that really helped

This script switches on those tweaks;  and switches them back off when done

* Audio can be quickly rebooted (for emergency live usage!)
* Can be run within X, or without.  If without, then X is shutdown until audio_mode ends
* The computer and screen are optionally kept awake throughout

<img src="screenshot2.png?raw=true" width="33%"> <img src="screenshot1.png?raw=true" width="33%">

## Usage
First check your configuration, try [realtimeconfigquickscan](https://github.com/raboof/realtimeconfigquickscan), and follow through what it says

If you'd like/need to edit audio_mode, then see http://wiki.linuxaudio.org/wiki/system_configuration for excellent information.  Though I hope this script can get you a long way to one-click x-run freeness

To make use of the script, download it, then maybe run `chmod u+x audio_mode.sh`. This will make it clickable and runnable with `./audio_mode.sh`

But before running, please configure it for your own setup.  Simply:

```bash
setup_apps() {
	xmessage 'Audio mode now active...
Run whatever apps you like,  then close me to exit' \
					 -buttons exit -default exit; }

setup_interfaces() { setup_apps; }
```

You can then open and close whatever apps you like.  Alternatively:

```bash
setup_apps() { guitarix; }
```

Would run audio_mode until guitarix quits

If you want to be able to quickly reboot your audio setup — something crashes, or there's a loose connection, or whatever — then you can get that with:

```bash
setup_apps() {
	jackd ... &
	zynaddsubfx &
	carla &
	# pass pids to reboot
	setup_reboot `pgrep carla` `pgrep zynaddsubfx`; }
```

## Notes
1. I've only tried this with lightdm.  Your computer configuration and kernel modules probably differ from mine.  I did get a big performance boost from removing unused kernel modules, but do edit the script however is appropriate for you

2. If running headless, then jumping back to the tty as X reloads can make it unhappy.  If this happens, try typing: `sudo lightdm service force-reload`

3. Check the script CONFIG section;  you may want to set `NETWORK=true` etc