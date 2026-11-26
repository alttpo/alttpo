#!/usr/bin/env python3
"""A standalone alttpo client that plays a snes9x movie (.smv) instead of a person.

It runs bsnes-headless (the bsnes-as `headless` target) with the alttpo scripts, joins a server like a player would, and
feeds the movie's controller 1 input to the game one frame at a time, paced to the SNES frame rate.

    tools/smv_client.py --movie ../tompa-zelda3.smv --server 127.0.0.1 --group test --name tompa

Movies: snes9x 1.43 SMV (version 1) files recorded from power-on. bsnes is cycle-accurate and snes9x 1.43 is not, so
the game lags (a frame where its logic does not run and the controller is not read) on different frames in each.
`--sync=logic` (the default) moves to the next movie frame only on frames where ALTTP's logic ran (its frame counter at
$7E001A advanced), so bsnes's extra lag frames don't use up movie input; `--sync=frame` plays one movie frame per
emulated frame. Neither keeps these movies in sync for long: see the note at the end of this file.
"""

import argparse
import os
import struct
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ALTTPO = os.path.dirname(HERE)
DEFAULT_SCRIPT = os.path.join(ALTTPO, "alttpo")
DEFAULT_BSNES = os.path.join(os.path.dirname(ALTTPO), "bsnes-as", "bsnes", "out", "bsnes-headless")
DEFAULT_ROM = os.path.join(os.path.dirname(ALTTPO), "alttp-us.sfc")

NTSC_FPS = 21477272.0 / 357366.0  # 60.0988
PAL_FPS = 21281370.0 / 425568.0

# snes9x joypad bits, in bsnes-headless's input order (bit 0 = up ... bit 11 = start):
SNES9X_BITS = [0x0800, 0x0400, 0x0200, 0x0100, 0x8000, 0x0080, 0x4000, 0x0040, 0x0020, 0x0010, 0x2000, 0x1000]
SYNC_LEFTRIGHT = 0x04
SYNC_HASROMINFO = 0x40


class Movie:
    """A snes9x 1.43 SMV file (version 1)."""

    def __init__(self, path):
        data = open(path, "rb").read()
        if data[:4] != b"SMV\x1a":
            raise ValueError(f"{path}: not an SMV file")
        version, self.uid, self.rerecords, self.frames = struct.unpack_from("<IIII", data, 4)
        if version != 1:
            raise ValueError(f"{path}: SMV version {version}; only snes9x 1.43 movies (version 1) are supported")
        self.controllers, options, _, self.sync = struct.unpack_from("<BBBB", data, 0x14)
        self.from_reset = bool(options & 1)
        self.pal = bool(options & 2)
        self.allow_left_right = bool(self.sync & SYNC_LEFTRIGHT)
        state_offset, input_offset = struct.unpack_from("<II", data, 0x18)

        meta_end = state_offset - 30 if self.sync & SYNC_HASROMINFO else state_offset
        self.author = data[0x20:meta_end].decode("utf-16-le", errors="replace").strip(" \0")
        self.rom_crc = None
        self.rom_name = ""
        if self.sync & SYNC_HASROMINFO:
            self.rom_crc = struct.unpack_from("<I", data, state_offset - 27)[0]
            self.rom_name = data[state_offset - 23:state_offset].rstrip(b"\0").decode("latin-1").strip()

        # from power-on, the embedded "state" is snes9x's gzipped 128 KiB SRAM buffer:
        self.sram = None
        if self.from_reset:
            try:
                self.sram = zlib.decompressobj(31).decompress(data[state_offset:input_offset])
            except zlib.error:
                self.sram = None

        # one 16-bit sample per frame per controller in the mask; there may be stale samples past the frame count:
        ports = [p for p in range(5) if self.controllers >> p & 1]
        if 0 not in ports:
            raise ValueError(f"{path}: the movie has no controller 1 input")
        stride = len(ports)
        count = min(self.frames + 1, (len(data) - input_offset) // (2 * stride))
        samples = struct.unpack_from(f"<{count * stride}H", data, input_offset)
        self.input = [to_mask(samples[i * stride]) for i in range(count)]


def to_mask(sample):
    return sum(1 << i for i, bit in enumerate(SNES9X_BITS) if sample & bit)


def bml_value(text):
    return str(text).replace("\n", " ")


def write_settings(directory, args):
    with open(os.path.join(directory, "alttpo.bml"), "w") as f:
        f.write("version: 2\n")
        f.write("server\n")
        f.write(f"  address: {bml_value(args.server)}\n")
        f.write(f"  group: {bml_value(args.group)}\n")
        f.write(f"  password: {bml_value(args.password)}\n")
        f.write("player\n")
        f.write(f"  name: {bml_value(args.name)}\n")
        f.write(f"  team: {args.team}\n")
        if args.color is not None:
            f.write(f"  color: 0x{args.color:04x}\n")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--movie", required=True, help="snes9x 1.43 .smv movie")
    p.add_argument("--rom", default=DEFAULT_ROM, help=f"ROM (default {DEFAULT_ROM})")
    p.add_argument("--script", default=DEFAULT_SCRIPT, help="alttpo script folder")
    p.add_argument("--bsnes", default=DEFAULT_BSNES, help="bsnes-headless binary")
    p.add_argument("--server", default="127.0.0.1")
    p.add_argument("--group", default="test")
    p.add_argument("--password", default="")
    p.add_argument("--name", help="player name (default: the movie's file name)")
    p.add_argument("--team", type=int, default=0)
    p.add_argument("--color", type=lambda s: int(s, 0), help="player color, 15-bit BGR, e.g. 0x7c00")
    p.add_argument("--no-connect", action="store_true", help="play without joining the server")
    p.add_argument("--speed", type=float, default=1.0, help="1 = real time, 2 = double speed, 0 = as fast as possible")
    p.add_argument("--sync", choices=["logic", "frame"], default="logic",
                   help="advance the movie on frames where the game's logic ran (default), or on every frame")
    p.add_argument("--offset", type=int, default=0,
                   help="frames to run before the movie starts (negative skips the movie's first frames)")
    p.add_argument("--at-end", choices=["idle", "exit"], default="idle",
                   help="when the movie ends, keep the player online with no input (default) or exit")
    p.add_argument("--status-every", type=float, default=5.0, help="seconds between status lines (0 = none)")
    p.add_argument("--quiet", action="store_true", help="don't print the script's log lines")
    args = p.parse_args()

    movie = Movie(args.movie)
    if not movie.from_reset:
        sys.exit("the movie starts from a snes9x savestate, which bsnes can't load; only power-on movies are supported")
    rom_crc = None
    if os.path.exists(args.rom):
        rom = open(args.rom, "rb").read()
        if len(rom) % 0x8000 == 512:
            rom = rom[512:]
        rom_crc = zlib.crc32(rom)
    if movie.rom_crc is not None and rom_crc is not None and movie.rom_crc != rom_crc:
        print(f"warning: the movie was recorded on ROM CRC {movie.rom_crc:08x} ({movie.rom_name}), "
              f"{args.rom} is {rom_crc:08x}", file=sys.stderr)
    if args.name is None:
        args.name = os.path.splitext(os.path.basename(args.movie))[0][:20]

    # bsnes_headless.py lives beside the headless target's sources: <bsnes>/out/bsnes-headless -> <bsnes>/target-headless
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(args.bsnes))), "target-headless"))
    from bsnes_headless import Headless, HeadlessError

    work = tempfile.mkdtemp(prefix="alttpo-smv-")
    settings_dir = os.path.join(work, "settings")
    os.makedirs(settings_dir)
    write_settings(settings_dir, args)
    extra = [f"--settings-dir={settings_dir}"]
    if movie.allow_left_right:
        extra.append("--allow-opposite-directions")
    sram = None
    if movie.sram:
        sram = os.path.join(work, "movie.srm")
        with open(sram, "wb") as f:
            f.write(movie.sram[:0x2000])  # ALTTP's cartridge SRAM is 8 KiB

    fps = PAL_FPS if movie.pal else NTSC_FPS
    print(f"movie: {os.path.basename(args.movie)} {movie.frames} frames ({movie.frames / fps / 60:.1f} min), "
          f"{movie.rerecords} rerecords, sync={args.sync}, player {args.name!r} in group {args.group!r} "
          f"on {args.server}", flush=True)

    printed_logs = 0

    def flush_logs(emu):
        nonlocal printed_logs
        if not args.quiet:
            for frame, level, text in emu.logs[printed_logs:]:
                print(f"[{frame}] {level}: {text}", flush=True)
        printed_logs = len(emu.logs)

    with Headless(args.bsnes, rom=args.rom, script=args.script, sram=sram, extra_args=extra) as emu:
        flush_logs(emu)
        if not args.no_connect:
            emu.exec("settings.connect()")
            flush_logs(emu)

        pointer = -args.offset if args.offset < 0 else 0
        lead_in = max(args.offset, 0)
        prev_counter = None
        lag = 0
        frame = 0
        start = time.monotonic()
        next_status = start + args.status_every
        ended = False
        try:
            while True:
                if lead_in > 0:
                    mask, lead_in = 0, lead_in - 1
                    consuming = False
                elif pointer < len(movie.input):
                    mask = movie.input[pointer]
                    consuming = True
                else:
                    if not ended:
                        ended = True
                        print(f"movie ended at frame {frame}", flush=True)
                        if args.at_end == "exit":
                            break
                    mask, consuming = 0, False

                # one round trip per frame: set the input, run the frame, read the frame counter:
                emu.proc.stdin.write(f"input 1 ${mask:03x}\nframe\nread $7e001a\n")
                emu.proc.stdin.flush()
                emu._answer()
                frame = int(emu._answer())
                counter = emu._answer()
                if consuming:
                    if args.sync == "frame" or counter != prev_counter:
                        pointer += 1
                    else:
                        lag += 1
                prev_counter = counter
                flush_logs(emu)

                now = time.monotonic()
                if args.status_every and now >= next_status:
                    next_status = now + args.status_every
                    module = emu.read(0x7E0010, 2).hex()
                    x, y = emu.read(0x7E0022, 2)[::-1].hex(), emu.read(0x7E0020, 2)[::-1].hex()
                    print(f"frame {frame} movie {pointer}/{len(movie.input)} lag {lag} module {module} x {x} y {y}",
                          flush=True)
                    flush_logs(emu)

                if args.speed > 0:
                    delay = start + frame / (fps * args.speed) - time.monotonic()
                    if delay > 0:
                        time.sleep(delay)
        except KeyboardInterrupt:
            pass
        except HeadlessError as e:
            flush_logs(emu)
            sys.exit(f"bsnes-headless: {e}")
        flush_logs(emu)


if __name__ == "__main__":
    main()

# Sync notes (tested on tompa-zelda3.smv and flagitious2-zelda.smv, both recorded on the US ROM, CRC 777aac2f):
# - frame for frame, both desync at once: bsnes reaches the title screen ~33 frames later and lags 5 more frames
#   loading the file select, so the file select and name entry inputs miss.
# - with --sync=logic both get through the menus, the intro and out of Link's house; the movies press opposite
#   directions (L+R, U+D) as snes9x allowed, which needs --allow-opposite-directions (set from the movie's LEFTRIGHT
#   sync flag). They then drift by a few pixels after the house-to-overworld load (bsnes lags 63 frames there; how
#   many snes9x 1.43 lagged is unknown) and Link ends up blocked by the bushes west of the house.
