# Linux (Ubuntu 26.04) setup on Macbook Pro 2016 (MacBookPro 13,3) 

Ubuntu setup scripts for my 2016 MacBookPro13,3 fresh installs.

This does personal setup work as well as hardware fixes. By default it can enable full passwordless sudo, install baseline developer packages, configure Wi-Fi firmware, build sound and Touch Bar drivers, and install a suspend workaround.

Before running it on any machine, review `config.env`. Set any `RUN_*` option to `0` to skip that module.

A fresh installation of Ubuntu 26.04 on this system leaves few things not working properly: Wi-fi, Audio, Touchbar, Webcam, Suspend

I initially followed:
- https://github.com/xtocdra/macbookpro13-2
- https://gist.github.com/almas/5f75adb61bccf604b6572f763ce63e3e
- http://inku.bot.nu/posts/fedora-macbook2017/
- https://github.com/davidjo/snd_hda_macbookpro
- https://github.com/rehans/macbook12-spi-driver-cachyos
- https://www.reddit.com/r/linuxmint/comments/1r348u6/no_audio_macbook_pro_loving_all_the_rest_new_life/

I could not get the touchbar to work on the new kernel 7.0.0 that ships with Ubuntu 26.04 so I used codex to fix it and write this set of installation scripts to streamline the process on fresh installs.

On my system I split the disk in 2 and installed MacOS Sonoma using OpenCore Legacy Patcher, then installed Ubuntu. In the OpenCore EFI boot menu, press space to see the additional booting options. The Ubuntu EFI option was not showing, I had to modify the OpenCore `EFI/OC/config.plist` file where I modified the field `Misc -> BlessOverride` by adding the path to the Ubuntu EFI file `\EFI\ubuntu\shimx64.efi`. I also set `HideAuxiliary = false`, this brought up the Ubuntu EFI option in OpenCore, so that I could boot it.

Once Ubuntu is installed, best would be to clone this repo on a usb key (Wifi will not work on first boot) and then proceed with the installation scripts below to first enable Wifi, connect to a network and then run all the patches for Audio, Touchbar, Camera and Suspend.

After installing the patches and rebooting, everything is working on my system.

## Fresh Install Flow

Run Wi-Fi first. It works offline by rendering the bundled Broadcom template with the detected Wi-Fi MAC address:

```bash
sudo ./wifi.sh
sudo reboot
```

After reboot, connect to Wi-Fi in Ubuntu, then run the full setup:

```bash
sudo ./install.sh
```

The full installer also runs Wi-Fi first, but on a fresh install the system usually needs the firmware file and a reboot before networking is usable.

For a preview without changing system files:

```bash
DRY_RUN=1 ./install.sh
```

## Modules

- `scripts/10-misc.sh`: passwordless sudo, baseline packages, GNOME auto-brightness setting, and placeholders for personal installs like Node or Chrome.
- `scripts/20-wifi.sh`: renders the Broadcom BCM43602 NVRAM template using the live Wi-Fi MAC address and installs it under `/usr/lib/firmware/brcm`.
- `scripts/30-sound.sh`: clones `davidjo/snd_hda_macbookpro` into `/var/lib/mbp13-linux-setup` and installs the Cirrus CS8409 driver via DKMS.
- `scripts/40-touchbar-camera.sh`: installs/restores the T1 iBridge Touch Bar and FaceTime HD camera path, including a forced iBridge reconfigure mode for resume.
- `scripts/50-suspend.sh`: configures suspend memory mode, disables PCI D3cold before sleep, and runs delayed Touch Bar recovery after resume.
- `scripts/90-report.sh`: prints a hardware and service report.

## Wi-Fi Template

The Broadcom template in `assets/wifi/brcmfmac43602-pcie.template.txt` is derived from my working BCM43602 file. The installer replaces:

- `{{WIFI_MACADDR}}` with the detected Wi-Fi interface MAC address.
- `{{WIFI_COUNTRY}}` with `WIFI_COUNTRY` from `config.env`.

To print the detected Wi-Fi MAC without installing files:

```bash
./wifi.sh --print-mac
```

## Notes

These scripts are written for Ubuntu 26.04 on MacBookPro13,2/13,3 with a T1 iBridge. They are not a generic Linux-on-Mac installer yet.

Full passwordless sudo is enabled by default because this is for my own fresh-install workflow. Disable it in `config.env` if you do not want that behavior.

Suspend defaults to `SUSPEND_MEMORY_SLEEP=s2idle` because `deep` sleep can resume with the Touch Bar on but the internal display still off on this MacBookPro13,3. To experiment with deeper sleep, set `SUSPEND_MEMORY_SLEEP=deep` in `config.env` and rerun `sudo ./scripts/50-suspend.sh`.
