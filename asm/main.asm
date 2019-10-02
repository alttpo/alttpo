architecture wdc65816
endian lsb

// patch over header values to extend ROM size from 8Mb to 16Mb:
{
    //origin 0x007FC0 // <- 7FC0 - Bank00.asm : 9173 (db "THE LEGEND OF ZELDA  " ; 21 bytes)
    //db $23, $4E

    origin 0x007FD5 // <- 7FD5 - Bank00.asm : 9175 (db $20   ; rom layout)
    //db #$35 // set fast exhirom
    db $30 // set fast lorom

    //origin 0x007FD6 // <- 7FD6 - Bank00.asm : 9176 (db $02   ; cartridge type)
    //db $55 // enable S-RTC

    origin 0x007FD7 // <- 7FD7 - Bank00.asm : 9177 (db $0A   ; rom size)
    db $0B // mark rom as 16mbit

    //origin 0x007FD8 // <- 7FD8 - Bank00.asm : 9178 (db $03   ; ram size (sram size))
    //db $05 // mark sram as 32k

    origin 0x1FFFFF // <- 1FFFFF
    db $00 // expand file to 2mb
}

// patch over PHA : PHX : PHY : PHD within original NMI routine in bank 00:
origin 0x0000CC
base   0x0080CC
    jml nmiHook

// give our NMI hook somewhere to return to:
origin 0x0000D0
base   0x0080D0
nmiReturn:;

// our NMI hook:
origin 0x100000
base   0x208000
    // ; Ensures this interrupt isn't interrupted by an IRQ
    // SEI
    //
    // ; Resets M and X flags
    // REP #$30
    //
    // ; Pushes 16 bit registers to the stack
    // PHA : PHX : PHY : PHD : PHB
nmiHook:
    // NOTE: we need to discover what we're patching over because it could be a JML $xxyyzz instruction
    // if the ROM is already patched with an NMI hook, such as for Randomizer.
    // This is the code we replaced in the main NMI routine with the JML instruction:
    pha ; phx ; phy ; phd

    // $7F7667[0x6719] = free RAM!

    sep #$30    // 8-bit accumulator and x,y mode

    // $7E0010 = main module
    lda $0010
    // $07 is dungeon
    cmp #$07
    beq validModule
    // $09 is overworld
    cmp #$09
    beq validModule
    // $0e can be dialogue/monologue or menu
    cmp #$0e
    bne invalidModule
    // check $0e submodule == $02 which is dialogue/monologue
    lda $0011
    cmp #$02
    beq validModule
invalidModule:
    // not a good time to sync state:
    jmp nmiHookDone

validModule:
    // build local packet to send to remote players:
    constant local = $7f7668
    constant local.location.lo = local + 0
    constant local.location.hi = local + 2
    constant local.x = local + 3
    constant local.y = local + 5
    constant local.z = local + 7
    constant local.xoffs = local + 9
    constant local.yoffs = local + 11
    constant local.oam_size = local + 13
    // Each OAM sprite is 4 bytes:
    // [0]: X coordinate on screen in pixels. This is the lower 8 bits.
    // [1]: Y coordinate on screen in pixels.
    // [2]: Character number to use. This is the lower 8 bits. See [3]
    // [3]: vhoopppc
    //   v - vertical flip
    //   h - horizontal flip
    //   p - priority bits
    //   c - the 9th (and most significant) bit of the character number for this sprite.
    constant local.oam_table.0 = local + 15
    constant local.oam_table.1 = local + 16
    constant local.oam_table.2 = local + 17
    constant local.oam_table.3 = local + 18

    lda $0FFF   // in dark world = $01, else $00
    asl
    ora $001B   // in dungeon = $01, else $00
    sta local.location.hi
    // if in dungeon, use dungeon room value:
    and #$01
    beq overworld   // if dungeon == 0, load overworld room number:

    // load dungeon room number as word:
    rep #$30        // 16-bit accumulator and x,y mode
    lda $00A0
    sta local.location.lo
    bra coords
overworld: // load overworld room number as word:
    rep #$30        // 16-bit accumulator and x,y mode
    lda $008A
    sta local.location.lo

coords:
    // load X, Y, Z coords:
    lda $0022
    sta local.x
    lda $0020
    sta local.y
    lda $0024
    sta local.z

    // xoffs = int16(bus::read_u16(0x7E00E2, 0x7E00E3)) - int16(bus::read_u16(0x7E011A, 0x7E011B));
    lda $00E2
    clc
    sbc $011A
    sta local.xoffs
    // yoffs = int16(bus::read_u16(0x7E00E8, 0x7E00E9)) - int16(bus::read_u16(0x7E011C, 0x7E011D));
    lda $00E8
    clc
    sbc $011C
    sta local.yoffs

sprites:
    // local.oam_size = 0;
    stz.w local.oam_size
    // Y is our index into tmp OAM
    constant oam_index = $0064 << 2
    ldy.w #oam_index
sprloop:
    // read oam.y coord:
    sep #$20        // 8-bit accumulator mode
    lda $0801,y

    // if (oam.y == $f1) continue; // sprite is off screen
    cmp #$f1
    beq sprcont

    // copy OAM sprite into table:
    pha
    rep #$20        // 16-bit accumulator mode
    lda.l local.oam_size
    tax
    sep #$20        // 8-bit accumulator mode
    pla

    // store oam.y into table:
    sta.l local.oam_table.1,x
    // copy oam.b0 into table:
    lda.w $0800,y
    sta.l local.oam_table.0,x
    // copy oam.b2 into table:
    lda.w $0802,y
    sta.l local.oam_table.2,x
    // copy oam.b3 into table:
    lda.w $0803,y
    sta.l local.oam_table.3,x

    // local.oam_size += 4
    rep #$20        // 16-bit accumulator mode
    clc
    lda.l local.oam_size
    adc.w #$0004
    sta.l local.oam_size

sprcont:
    // y += 4
    iny
    iny
    iny
    iny
    // if (y < $70) goto sprloop;
    constant oam_index_max = $0070 << 2
    cpy #oam_index_max
    bcc sprloop

nmiHookDone:
    rep #$30
    jml nmiReturn
