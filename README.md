# MacBookPro13 Linux Setup

Opinionated Ubuntu setup scripts for my MacBookPro13,2 / MacBookPro13,3 fresh installs.

This repo intentionally does personal setup work as well as hardware fixes. By default it can enable full passwordless sudo, install baseline developer packages, configure Wi-Fi firmware, build sound and Touch Bar drivers, and install a suspend workaround.

Before running it on any machine, review `config.env`. Set any `RUN_*` option to `0` to skip that module.

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
- `scripts/40-touchbar-camera.sh`: installs/restores the T1 iBridge Touch Bar and FaceTime HD camera path.
- `scripts/50-suspend.sh`: configures suspend memory mode and disables PCI D3cold before sleep.
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
