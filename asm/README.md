What it is
---

This directory contains the ASM code (WDC 65816) which directly patches an SMC ROM dump of ALTTP.
Currently only tested against US v1.2 version of the ROM.

Requires [bass](https://code.byuu.org/bass) to assemble, see the `build.sh` bash script I use for
testing and development.

What it does
---

This patch to the ALTTP ROM enhances the game to add support for rendering a remote player's sprites
onto the local player's screen if the two players happen to be in the same area/room.

How it works
---

In order to render the remote player's sprites into the local player's game, the OAM table and VRAM
sprite tile data (graphics) must be updated every frame that the remote player is on the screen.
The challenge is in finding free VRAM space to use for synchronizing the remote player's graphics to.

After some not-so-extensive testing, I've identified 5 16x16 sprite slots that I consider free space.

![Sprite VRAM](vram.png)

(sorry for weird colors on some of these sprites - this is just a result of using a single palette for
all of the sprites)

1. `$40` - this is that weird looking 16x16 area immediately left of the signpost sprite. I've never
seen it used but I could be wrong.
1. `$64` - this is the two 16x16 blocks for the "blob" sprite that some enemies transform into after
using the magic powder on them. These are used so infrequently in casual play let alone during speedruns,
tournaments, or randomizer races that I consider them practically free.
1. `$CB` - this is the two 16x16 blocks for the "bubble" sprites on the second to last row above the
fairy sprites. I don't think they're ever used but I could be wrong.

You may ask yourself, why not use the two follower/tag-along sprites immediately below Link's body and
head? Basically, because these sprites *may* be used by the local player when gaining a follower. I'd
have to change the CHR mapping from static to dynamic based on whether the local player has a follower
or not.

In total we have 5 16x16 sprite blocks free to map the remote player's sprite data to now. We only
waste 2 8x8 blocks since Link really only requires 4 16x16 blocks and 2 8x8 blocks to render his
body, shield, and sword.

WRAM interface
---

This patch communicates with the external world via WRAM. It is assumed that either an emulator or a
console hardware unit (like the SD2SNES) is able to read and write blocks of WRAM that the game will
then freely access. We can think of it as basically a memory-mapped network driver. It is also
assumed that this external interface (emulator or hardware) reading/writing blocks of WRAM is also
able to communicate with another hardware console or emulator running a copy of the patched ROM via
a network of some kind.

There are two defined WRAM block addresses, one representing the local player's data packet to be
sent to the remote player, and another representing the remote player's data packet that was received
from the remote player.

* `$7F7700` - local player's data packet
* `$7F8200` - remote player's data packet

Both data packets share an identical format and there is no need for external processing of the data
within these packets. The data packet is natively produced by this ROM patch and intended for direct
consumption by this ROM patch as well.

    struct Packet {
        // positional information about the player:

        // -------- ------wd rrrrrrrr rrrrrrrr
        //   w: 0 = light world, 1 = dark world
        //   d: 0 = overworld, 1 = dungeon
        //   r: 16-bit area/room number (overworld/dungeon)
        uint32 location;
        uint16 x;
        uint16 y;
        uint16 z;
        // screen scroll offset from top-left corner of area:
        uint16 xoffs;
        uint16 yoffs;

        // visual aspects of player taken from SRAM at $7EFxxx:
        uint8  sword;  // $359
        uint8  shield; // $35A
        uint8  armor;  // $35B

        // DMA source address words read from WRAM at $7E0AC0..$7E0ACA which point to bank $10:
        uint16 dma7E_addr[6];
        // DMA source address words from from WRAM at $7E0ACC..$7E0AD6 which point to bank $7E:
        uint16 dma10_addr[6];

        // Number of OAM sprites used to render Link:
        uint8        oam_count;
        // Main OAM table data (fixed array of max 12 OAM sprites):
        // (found in WRAM at $7E0800)
        OAMSprite    oam_table[12];
        // Extended OAM table data (fixed array of max 12 OAM sprites):
        // (found in WRAM at $7E0A20)
        OAMSpriteExt oam_table_ext[12];
    }

    // 4 byte struct that represents a hardware OAM sprite:
    struct OAMSprite {
        uint8 b0; // xxxxxxxx
        uint8 b1; // yyyyyyyy
        uint8 b2; // cccccccc
        uint8 b3; // vhoopppc
    }

    // 1 byte struct represents the extra 2 bits that couldn't fit in the 4 byte OAM struct:
    struct OAMSpriteExt {
        uint8 b4; // ------sx
    }

It is recommended to wrap the data packet with a message envelope when sending on the wire to
include things like a packet version, an identifying header, and possibly a checksum for error
detection / correction purposes. This message envelope must be stripped away when copying the
data into WRAM though since the ROM patch only recognizes the `struct Packet` raw binary layout
described above.
