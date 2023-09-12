# fz_fw_update

Flipper Zero firmware update script (targeting [Unleashed Firmware](https://github.com/DarkFlippers/unleashed-firmware))

gnu/linux specific

```
update.sh - Flipper Zero firmware update script
usage: update.sh [options] [command]
  commands:
    check          - check for update
    update         - update firmware
    install <file> - install from local file (implies "force")
    list           - list devices
    rel            - list available releases
    cli            - open interactive cli
  options:
    -f            - force update
    -d <device>   - specify flipper device manually (default - auto)
    -v <variant>  - release variant (default - "e")
    -r <release>  - firmware release (default - latest)
    -D            - latest development build
```
