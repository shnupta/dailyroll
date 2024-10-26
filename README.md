# dailyroll

Building for Raspberry Pi Zero W:
```
zig build -Dtarget=arm-linux-gnueabihf -Dcpu=arm1176jz_s
```

TODO:
- [ ] Make modules adhere to an interface.
- [ ] Load dailyroll configuration from some toml-like file (ziggy?)
- [ ] Construct modules dynamically based on this configuration
- [ ] Can have things like title, section spacing etc in config as well
- [ ] Handy methods for formatting
- [ ] API keys in config (section per module config)

