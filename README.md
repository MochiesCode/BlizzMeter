# BlizzMeter

A standalone copy of the Blizzard Damage Meter (`Blizzard_DamageMeter`, 12.1.0.69933), meant as a base for a custom meter.

## How it maps to the Blizzard source

Each file is a port of the matching Blizzard file, with `DamageMeter` renamed to `BlizzMeter` in every global (mixins, templates, frames, constants, saved variables, menu tags):

| BlizzMeter | Blizzard_DamageMeter |
| --- | --- |
| `BlizzMeter.lua/.xml` | `DamageMeter.lua/.xml` |
| `BlizzMeterSessionWindow.lua/.xml` | `DamageMeterSessionWindow.lua/.xml` |
| `BlizzMeterSourceWindow.lua/.xml` | `DamageMeterSourceWindow.lua/.xml` |
| `BlizzMeterEntry.lua/.xml` | `DamageMeterEntry.lua/.xml` |
| `BlizzMeterSettingsDropdownButton.lua/.xml` | `DamageMeterSettingsDropdownButton.lua/.xml` |
| `BlizzMeterConstants.lua` | `DamageMeterConstants.lua` |
| `BlizzMeterEditMode.lua/.xml` | `EditModeDamageMeterSystemMixin` / template in `Blizzard_EditMode` |
| `BlizzMeterSecrets.lua` | (new) helpers for secret values |

Every place where the code differs from Blizzard's is marked with a `BlizzMeter:` comment.

## Edit Mode

Addons can't register their own Edit Mode systems, so BlizzMeter follows the Blizzard Damage Meter's (`BlizzMeterEditMode.lua`):

- The meter is anchored to the Blizzard meter's Edit Mode frame, so it takes that frame's position and size, live while it's dragged or resized, and copies its scale.
- Every Damage Meter setting in Edit Mode (style, numbers, bar height, padding, opacity, background, text size, visibility, spec icons, class colors) is mirrored.
- Turning on the Damage Meter in Edit Mode shows BlizzMeter's preview, the same as Blizzard's.

The Blizzard meter keeps running underneath so it can still be moved and configured in Edit Mode, but its windows are moved into a hidden frame so only BlizzMeter shows. Disabling BlizzMeter brings the Blizzard meter back unchanged.

## Saved variables

Window setup (tracked type, segment, lock, interactivity, minimized, extra windows) is saved per character in `BlizzMeterPerCharacterSettings`. On first load it's copied from the Blizzard meter's saved windows.

Extra windows also save their position and size there. Blizzard keeps these in the client's layout cache, which goes by frame name instead. An extra window with no saved position starts where the matching Blizzard window was, if you had moved that one.

## Changes from the Blizzard meter

- Player names are shown without their realm ("Name-Realm" becomes "Name"), in the meter and in the spell breakdown. NPC names are left alone.

## Differences in combat

During combat, the game gives addons most damage meter data as *secret values*. Addon code can display them but can't compare them or do math on them. The Blizzard meter isn't affected because its code isn't addon code. While combat restrictions are active, BlizzMeter shows:

- **Complete numbers** without the percentage, the same as Compact.
- **Deaths** without the time of death.
- **Class colors off:** default bar colors instead of ally and enemy colors, and no enemy faction icons.
- **Clicking a bar** opens the spell breakdown only for your own bar. Clicks on other bars do nothing until combat ends.
- **Spell breakdown:** class colors on bars that would use the creature color.

The meter redraws with the full display as soon as combat ends.

## Updating to a new Blizzard build

Get the new `Interface/AddOns/Blizzard_DamageMeter` from [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) (or export it in game with `/console exportInterfaceFiles code`). Apply the same renames (`DamageMeter` to `BlizzMeter`, `DAMAGE_METER_DEFAULT_BAR_HEIGHT` to `BLIZZMETER_DEFAULT_BAR_HEIGHT` and so on) and diff it against these files. Bring over the Blizzard changes and keep the `BlizzMeter:` adaptations.
