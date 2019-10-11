# alttp-multiplayer
ALTTP Multiplayer ROM hack and supporting scripts for [bsnes-angelscript](//github.com/JamesDunne/bsnes-angelscript).

See [here](romhack/README.md) for documentation on the ROM hack and how it works.

Download nightly binary builds of bsnes-angelscript here:
https://cirrus-ci.com/github/JamesDunne/bsnes-angelscript

See a demo video: https://www.youtube.com/watch?v=_MTfXCUXawg

Instructions to reproduce the demo with two emulators running on your machine:
1. Download a nightly build of bsnes-angelscript for your platform above.
1. Download a nightly build of bass assembler
1. [OS X Only] In a Terminal tab, run `sudo ifconfig lo0 alias 127.0.0.2 up`.
2. Launch one instance of `bsnes-angelscript`(`.exe`)
3. Run `./test.sh` script in a new Terminal tab to open instance 2
4. The IP address in instance 1 should work as-is so just click Start there.
5. In instance 2 press the Swap button to swap the two values so the Server IP is `127.0.0.2` and the client IP is `127.0.0.1`.
6. Click Start on both instances and load a saved state or play through the game on both emulators to see both Link avatars on both screens.

# Internet play
I'm working on a WebRTC-based solution to enable players to find one another and play together over the public Internet.

This should be technically possible to do right now if both players are savvy enough to open UDP port `4590` on their home routers and exchange their public IPv4 addresses with one another.
