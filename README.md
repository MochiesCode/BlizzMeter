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
| `BlizzMeterOptions.lua` | (new) the options panel |
| `BlizzMeterSecrets.lua` | (new) helpers for secret values |

Every place where the code differs from Blizzard's is marked with a `BlizzMeter:` comment.

## Edit Mode

Addons can't register their own Edit Mode systems, so BlizzMeter follows the Blizzard Damage Meter's (`BlizzMeterEditMode.lua`):

- The meter is anchored to the Blizzard meter's Edit Mode frame, so it takes that frame's position and size, live while it's dragged or resized, and copies its scale.
- The Damage Meter's other Edit Mode settings (style, numbers, bar height, padding, opacity, background, text size, visibility, spec icons, class colors) only give BlizzMeter's options their starting values. After that, change them in BlizzMeter's options; changing them in Edit Mode has no effect on BlizzMeter.
- Turning on the Damage Meter in Edit Mode shows BlizzMeter's preview, the same as Blizzard's.

The Blizzard meter keeps running underneath so it can still be moved and resized in Edit Mode, but its windows are moved into a hidden frame so only BlizzMeter shows. Disabling BlizzMeter brings the Blizzard meter back unchanged.

## Options

Open them from Options > AddOns > BlizzMeter, with `/bm`, or from "BlizzMeter Options" in a meter window's settings menu.

**Appearance** has every Damage Meter style setting from Edit Mode, with the same ranges and choices, plus:

- **Spec Icon Shape:** Square (Blizzard's), Circle, or Circle with Ring (masked inside the `services-cover-ring` atlas). Applies to class and spec icons; spell icons stay square.
- **Bar Color:** shown while Show Class Color is off. Every bar uses this color instead of Blizzard's default, ally and enemy colors.
- **Always Show Your Bar:** when your bar is scrolled out of view, it's pinned to the top or bottom edge of the window (Blizzard's behavior). Turn off to let it scroll away like the others.
- **Show Realm Names:** shows players from other realms as "Name-Realm" instead of "Name".
- **Text Outline:** turn off to remove the black outline and shadow from the names and numbers on the bars.
- **Text Color:** color of the names and numbers on the bars. Class-colored names in the spell breakdown keep their class color.

**Copy Edit Mode Settings** replaces the options that Edit Mode also has with the values from your current Edit Mode layout.

Because addon code can't write Edit Mode settings without tainting the Blizzard meter, the two don't stay in sync.

## Saved variables

Options are saved for the whole account in `BlizzMeterSettings`.

Window setup (tracked type, segment, lock, interactivity, minimized, extra windows) is saved per character in `BlizzMeterPerCharacterSettings`. On first load it's copied from the Blizzard meter's saved windows.

Extra windows also save their position and size there. Blizzard keeps these in the client's layout cache, which goes by frame name instead. An extra window with no saved position starts where the matching Blizzard window was, if you had moved that one.

## Changes from the Blizzard meter

- Player names are shown without their realm ("Name-Realm" becomes "Name"), in the meter and in the spell breakdown, unless Show Realm Names is on. NPC names are left alone.
- Class and spec icons are round and framed by a ring by default (see Spec Icon Shape).

## Differences in combat

During combat, the game gives addons most damage meter data as *secret values*. Addon code can display them but can't compare them or do math on them. The Blizzard meter isn't affected because its code isn't addon code. While combat restrictions are active, BlizzMeter shows:

- **Complete numbers** without the percentage, the same as Compact.
- **Deaths** without the time of death.
- **No enemy faction icons** next to names (shown with class colors on).
- **Clicking a bar** opens the spell breakdown only for your own bar. Clicks on other bars do nothing until combat ends.
- **Spell breakdown:** class colors on bars that would use the creature color.

The meter redraws with the full display as soon as combat ends.

## Updating to a new Blizzard build

Get the new `Interface/AddOns/Blizzard_DamageMeter` from [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) (or export it in game with `/console exportInterfaceFiles code`). Apply the same renames (`DamageMeter` to `BlizzMeter`, `DAMAGE_METER_DEFAULT_BAR_HEIGHT` to `BLIZZMETER_DEFAULT_BAR_HEIGHT` and so on) and diff it against these files. Bring over the Blizzard changes and keep the `BlizzMeter:` adaptations.
