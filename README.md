# fz_fw_update

Flipper Zero firmware update script

```
usage: update.sh [options] [command]
  commands:
    check  - check for update
    update - update firmware to latest
    list   - list devices
    cli    - open interactive cli
  options:
    -f            - force update
    -d <device>   - specify flipper device manually (default - auto)
    -v <variant>  - release variant (default - "e")
    -F <firmware> - firmware (default "DarkFlippers/unleashed-firmware")
    -r <release>  - firmware release (default - latest)
```
