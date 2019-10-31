# alttp-multiplayer
ALTTP Multiplayer ROM hack and supporting scripts for [bsnes-angelscript](//github.com/JamesDunne/bsnes-angelscript).

See [here](romhack/README.md) for documentation on the ROM hack and how it works.

See a demo video: https://www.youtube.com/watch?v=_MTfXCUXawg

Instructions to reproduce the demo with two emulators running on your machine:
**PREREQUISITES**: You need your own copy of the ALTTP game ROM image. DO NOT ASK ME FOR ONE; I will ignore you so hard. It is illegal to redistribute ROM images.

1. Download a nightly build of bsnes-angelscript here:
https://cirrus-ci.com/github/JamesDunne/bsnes-angelscript
1. Download a nightly build of bass assembler here:
https://cirrus-ci.com/github/JamesDunne/bass
1. Make a safe backup copy of your original ALTTP ROM file!!!
1. COPY (do not MOVE) your ALTTP ROM file into this `romhack/` directory and rename it to `alttp.smc`.
1. Run `bass -m alttp.smc main.asm` to patch the `alttp.smc` file. Note you'll need `bass` (downloaded from step 2) on your $PATH or you can copy the `bass`(`.exe`) file from the nightly build ZIP file here.
1. [Mac OS X Only] In a Terminal tab, run `sudo ifconfig lo0 alias 127.0.0.2 up`.
1. Launch TWO instances of `bsnes-angelscript`(`.exe`) (downloaded from step 1)
1. Move the emulator windows so that they don't overlap.
1. In both instances, load the `alttp.rom` patched file.
1. In both instances, Tools > Load Script... and select `angelscript/alttp-romhack.as` file.
1. In instance 1, the IP addresses should work as-is so just click Start there.
1. In instance 2 press the Swap button to swap the two values so the Server IP is `127.0.0.2` and the client IP is `127.0.0.1`.
1. Click Start on both instances and load a saved state or play through the game on both emulators to see both Link avatars on both screens.

# Internet play
I'm working on a WebRTC-based solution to enable players to find one another and play together over the public Internet.

This should be technically possible to do right now if both players are savvy enough to open UDP port `4590` on their home routers and exchange their public IPv4 addresses with one another.
