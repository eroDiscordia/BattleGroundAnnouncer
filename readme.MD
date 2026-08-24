# Battleground Announcer (BGA)

One World of Warcraft addon, two battleground callers. Battleground
Announcer gives you click-to-call button panels for **Arathi Basin** and
**Warsong Gulch** that post ready-made callouts straight to `/bg` chat, so
you don't have to type them out mid-fight.

- Interface: 3.3.5a (WotLK, Interface `30300`)
- Each panel shows automatically only while you're inside its own
  battleground, and hides everywhere else.
- Both panels can be independently moved and resized (see
  [Moving and resizing](#moving-and-resizing) below).

## Installation

1. Unzip into your `Interface/AddOns/` folder so the path reads
   `Interface/AddOns/BattlegroundAnnouncer/BattlegroundAnnouncer.toc`.
2. If you previously used the separate **ABIncoming** or **WSGIncoming**
   addons, delete those folders first — Battleground Announcer replaces
   both (see [Upgrading](#upgrading-from-abincoming--wsgincoming) below).
3. Restart or reload WoW (`/reload`) and enable **Battleground Announcer**
   on the character select AddOns list if needed.

## Moving and resizing

No slash command needed, ever:

- **Hold Shift and drag** the panel to move it.
- **Hold Ctrl and scroll** the mouse wheel over it to resize it.

This works regardless of the panel's lock state. `/bga ab lock` /
`/bga wsg lock` are now purely a status label (shown in the panel's
title) - they no longer block Shift-drag or Ctrl-scroll.

## Arathi Basin panel

A circular node wheel with five nodes: **Gold Mine**, **Blacksmith**,
**Farm**, **Stables**, **Lumber Mill**.

1. Click a node.
2. The wheel swaps to numbers **1–5** in the same spots.
3. Click a number to send:

   ```
   <Node>: <N> Incoming
   ```

   For example, clicking Blacksmith then 2 sends `Blacksmith: 2 Incoming`.

Clicking anywhere outside the wheel while numbers are showing resets back
to the node wheel without sending anything.

## Warsong Gulch panel

Two top-level buttons, **Offense** and **Defense**, with a status label
below them and the callout buttons arranged in aligned rows beneath that:

```
   Offense              Defense

     Tunnel        Ramp

         WSG Caller 100%

  GraveYard          Flag Room

              Roof
```

| Button       | Reveals                                             | Message sent               |
|--------------|--------------------------------------------------------|-----------------------------|
| **Offense**  | Tunnel, Ramp, GraveYard, Flag Room, Roof                | `Flag Carrier @ <spot>`     |
| **Defense**  | Tunnel, Ramp                                            | `Incoming: <spot>`          |

Tunnel and Ramp sit in the same spots for both menus, side by side, just
below Offense/Defense. Defense only reveals those two; Offense reveals all
five, with the status label centered below Tunnel/Ramp, GraveYard and
Flag Room lined up side by side below that, and Roof centered at the
bottom.

Clicking anywhere outside the buttons while a submenu is open resets back
to the main Offense/Defense buttons without sending anything.

## Slash commands

Everything is controlled through a single `/bga` prefix:

```
/bga ab <command>    - control the Arathi Basin panel
/bga wsg <command>   - control the Warsong Gulch panel
```

| Command             | Effect                                              |
|---------------------|------------------------------------------------------|
| `lock`              | Mark as locked (status label only; Shift-drag/Ctrl-scroll still work) |
| `unlock`            | Mark as unlocked                                       |
| `scale <0.5-2.0>`   | Set size precisely                                    |
| `show`              | Force the panel to show                               |
| `hide`              | Force the panel to hide                               |
| `auto`              | Resume automatic show/hide based on your current zone |
| `reset`             | Reset the panel's position and size to default        |

**Examples**

```
/bga ab lock
/bga ab scale 1.2
/bga wsg unlock
/bga wsg show
/bga wsg auto
```

Typing `/bga` alone (or an unrecognized subcommand) prints this same
command summary in-game.

## Upgrading from ABIncoming / WSGIncoming

Battleground Announcer replaces the two older, separate addons. It uses
its own SavedVariables table (`BGADB`), so position, lock state, and scale
from the old addons will **not** carry over automatically — both panels
start at their default position and scale once, then remember whatever
you set from there.

Remove the old `ABIncoming` and `WSGIncoming` folders from
`Interface/AddOns/` to avoid duplicate panels and conflicting slash
commands.
