This directory contains the ASM code which directly patches an SMC ROM dump of ALTTP. Currently only
tested against [US] v1.2 version of the ROM.

Requires [bass](https://code.byuu.org/bass) to assemble, see the `build.sh` bash script I use for
testing and development.

WRAM interface
---

This patch to the ALTTP ROM enhances the game to add support for rendering a remote player's sprites
onto the local player's screen if the two players happen to be in the same area/room.
