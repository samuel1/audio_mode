# audio_mode
One click audio configuration for linux



## About
I tried so many things, like running headless etc.  Before finding audio tweaks that really helped

This script switches on those tweaks;  and switches them back off when done

* Audio can be quickly rebooted (for emergency live usage!)
* Can be run within X, or without.  If without, then X is shutdown until audio_mode ends
* The computer and screen are optionally kept awake throughout

With and without X:<br>
<img src="screenshot2.png?raw=true" width="33%"> &nbsp; <img src="screenshot1.png?raw=true" width="33%">



## Usage
Simply (1) run the script to enter audio mode.  Then (2) open and close any audio apps you like, until you exit audio_mode.  At which point it will restore the computer for normal usage (reload kernel modules, de-nice X, reset hd swappiness, restart networking, etc)



### Further configuring audio_mode
The rest of this section explains how to get live rebooting, and how to automate the loading of jack/apps

However this requires ladish or a little scripting...

Ladish is maybe the easier option:  Using Claudia, Gladish or another program, create a ladish studio, fill it with apps, configure jack, and save the studio.  The studio manager will then be able to start/stop your studio from its menus

Once you've got this working, audio_mode will also be able to start/stop your studios.  To run a particular studio with audio_mode, simply run `./audio_mode.sh ladish my_studio_name`

<br>

The second option is to write a script yourself that loads and links the apps you want.  The script must block until you want audio mode to end.  You can run it with `./audio_mode.sh script /path/to/my/script.sh`

The function `setup_guitarix()` within audio_mode.sh is an example of this. And shows how to get the advantages of live rebooting and 'auto-closing' audio_mode when you quit an app.  Try it with `./audio_mode.sh guitarix`.  Note that it assumes you're starting jack separately, or from within guitarix



### Extra help
First check your configuration, try [realtimeconfigquickscan](https://github.com/raboof/realtimeconfigquickscan), and follow through what it says

If you'd like/need to edit audio_mode.sh, then see http://wiki.linuxaudio.org/wiki/system_configuration for excellent information.  Though I hope this script gets you a long way to one-click x-run freeness



## Installation
Create a `~/bin` folder if you dont have one, then:
```bash
cd ~/bin
git clone https://github.com/samuel1/audio_mode.git
```

You can then run audio_mode with one of:
```bash
~/bin/audio_mode/audio_mode.sh
~/bin/audio_mode/audio_mode.sh ladish my_studio_name
~/bin/audio_mode/audio_mode.sh script /path/to/my_script.sh
~/bin/audio_mode/audio_mode.sh guitarix
```

If you did clone to `~/bin` and you want to add audio_mode to your applications menu, or make it clickable from your desktop, you can run:
```bash
ln -s ~/bin/audio_mode/audio_mode.desktop ~/.local/share/applications/audio_mode.desktop

ln -s ~/bin/audio_mode/audio_mode.desktop ~/Desktop/audio_mode.desktop
```



## Notes
1. I've only tried this with lightdm.  Your computer configuration and kernel modules probably differ from mine.  So do edit the script however is appropriate for you

2. If running headless, then jumping back to the tty as X reloads can make it unhappy.  If this happens, try typing: `sudo lightdm service force-reload`

3. Check the script CONFIG section;  you may want to set `NETWORK=true` etc

4. Wifi is also shutdown while audio_mode is active (as it can cause x-runs).  To browse the web during audio_mode, try: `sudo service network-manager start`, or delete that line