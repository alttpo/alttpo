How is ALttPO different from emu-coop and others?
* You can see other players in real time when they're in the same location as you
* Sound effects from other players on the same screen are synced
* Custom player sprites are supported and are visible to other players
* Nearly all game state that is synced is synced at the full 60fps that the game runs at
* Network communication among players is done via raw UDP sockets, not over IRC or other TCP-based means
* Multiple players (more than two) are supported in the same game
* Designed in a peer-to-peer fashion with a custom server responsible only for peer discovery and traffic forwarding between peers

Is it open-source?
* Yes! Any and all help is welcome.
* https://github.com/JamesDunne/alttp-multiplayer
* https://github.com/JamesDunne/bsnes-angelscript

Does it run on my system?
* If your system is Windows, MacOS, or Linux, then yes.
* Cross-platform support is one of the goals of the project.
* If your system is not Win/Mac/Linux then it would require some porting effort but that effort is entirely contained within the bsnes project and not ALttPO itself.

What is ALttPO implemented in?
* AngelScript 2.34.0 https://www.angelcode.com/angelscript/sdk/docs/manual/doc_script.html
* C++17 extensions on the bsnes emulator to integrate AngelScript support

Is it compatible with real SNES consoles?
* Not currently.
* At some point in the future this avenue could be explored but for now it requires the bsnes emulator.

Does it work with any SNES emulator?
* Not currently.
* Only bsnes is supported at this time.

Why bsnes and why not snes9x or my favorite emulator?
* Bsnes was chosen for its high emulation accuracy and for the quality and maintainability of its codebase
* Bsnes natively supports multiple platforms out of the box, not just Windows
* Bsnes has its own cross-platform GUI library for handling windows, buttons, checkboxes, labels, etc.
* Other emulators could be supported in the future but this would require porting effort; time is better spent on improving ALttPO right now rather than extending support to more emulators.

What ALTTP ROMs are supported?
* US v1.2
* JP v1.0
* VeeTorp's Randomizer ROMs based on JP 1.0 as of v31

What world state IS synced?
* Temporary real-time overworld area changes e.g. picked up bushes, stones, signs, cut grass, shovel dig sites
* Permanent overworld area changes e.g. lumberjack tree cut down, revealed secrets, bombed walls
* Permanent underworld area changes e.g. doors opened, bombed, chests opened
* Underworld torch lit/unlit state
* General progress indicators for NPCs e.g. bottle salesman, hobo, dwarven swordsmiths, witch
* Temporary objects on screen:
  * Bombs
  * Arrows
  * Ice rod shots
  * Fire rod shots
  * Somaria blocks
  * Moving gravestones
  * Explosions

What world state IS NOT synced?
* Temporary real-time underworld area changes e.g. picked up pots, star tile changes, trap floors, trap doors
* Enemies on the screen
* Item drops on the screen
* Players cannot directly interact but can indirectly harm one another via bombs

Which player items ARE synced?
* Bow & silver upgrade
* Boomerang (blue, red)
* Hookshot
* Mushroom, powder (randomizer note: cannot lose mushroom once gained)
* Fire rod
* Ice rod
* Bombos medallion
* Ether medallion
* Quake medallion
* Lantern
* Hammer
* Shovel, flute
* Bug net
* Book of Mudora
* Bottle count (NOT contents)
* Cane of Somaria
* Cane of Byrna
* Magic Cape
* Magic Mirror

Which player items ARE NOT synced?
* Arrows count
* Bombs count
* Rupees count
* Bottle contents (only new pre-filled bottles are synced)
* Life meter
* Magic meter

Which player stats ARE synced?
* Pegasus boots
* Mitts/gloves
* Flippers
* Moon pearl
* Arrows capacity
* Bombs capacity
* 1/2 and 1/4 magic
* Sword level (fighter, master, tempered, butter)
* Shield level (no shield, fighter, fire, mirror)
* Armor level (aka mail/tunic color, green, blue, red)
* Heart containers and quarter heart pieces

What dungeon progress IS synced?
* Pendants and crystals
* Dungeon big keys
* Dungeon compasses
* Dungeon maps

What dungeon progress IS NOT synced?
* Dungeon small keys
