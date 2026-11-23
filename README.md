# Notes+

Write notes and track goals in RuneScape.

## Features

- Give each note a title, subject, color, and sprite icon.
- Organize notes into categories with their own names, colors, and icons.
- Search notes by title, subject, or tracking label.
- Drag notes and categories to reorder them.
- Track supported goals with progress bars, item counts, and requirement lists.
- Attach gear setups and action bar references.
- Share individual notes, a selected group, or all your notes.
- Preview notes in a journal-style view.

Drag the window by its header to move it. Grab an edge or corner to resize it.

### Goal tracking

- Skill levels and currencies
- Boss kill counts and collection log items
- Combat Achievements
- Clue completions, including Tetracompasses
- Area Tasks achievements
- Slayer and Reaper tasks
- Quests, cape requirements, and Reaper Crew
- Ports exploration, trade goods, and resources
- Invention components and research unlocks
- Gathering and production goals
- General unlocks, including Player-Owned Farms and Anachronia
- Weekly and monthly D&Ds
- Boss timers

For collection goals, select multiple items and give them different quantities, or use **Set all** to apply the same target to the selection.

Each tracked note has separate options for a chat message or popup when its goal is completed. Quest tracking can also notify you when a quest becomes ready to start.

Gathering and production goals count new items while the plugin is running.

### Gear and action bars

Attach a gear setup by choosing items for each slot or copying your currently equipped gear.

You can also copy an action bar into a note. Display the bar in-game so Notes+ can detect it.

Hover over an icon for a quick preview or click it to open the full view.

### Colors, icons, and categories

Use the color picker or enter a hex code to change a note’s color. Search game sprites and items with the icon picker.

Create categories from the sidebar, then use their menus to rename them or change their appearance. Deleting a category moves its notes to **Uncategorized**.

### Settings

- Enable or disable the plugin.
- Choose a side-by-side or vertically scrolling settings layout.
- Set hotkeys for the notes window and settings.
- Open the notes window automatically on startup.
- Hide progress bars for a more compact layout.
- Choose where each note’s popup notifications appear when enabled.

Display settings let you change the window opacity, font size, default subject visibility, and completion popup position.

Notes and settings are saved separately for each character on the current device.

### Sharing and importing

Press **Share** in the main window to choose which notes to export. You can select or deselect individual notes, select all, or clear the selection. You can also share a single note from its editor.

Share codes include note text, categories, colors, icons, tracking goals, attachments, and notification choices.

The share screen shows a character count. Codes can contain up to **9,999 characters**. If your selection exceeds the limit, share fewer notes at a time.

Click the exported text field, then press **Ctrl+A** and **Ctrl+C** to copy the code. **Copy** produces plain text for pasting into a message.

Import adds shared notes alongside your existing notes.

### Backups

Keep a backup by exporting your notes with **Share** and saving the codes in a text file. Export several smaller groups if needed to stay within the character limit.

Use share codes to move notes between devices.

## Data protection

Notes+ runs in the RuneScape client. Notes, character profiles, and settings are stored locally.

Character tracking access identifies the character and loads the correct profile. Chat access supports completion notifications and helps track certain variables.

Sprite and item searches use information available through the client. Notes+ has no analytics, external network requests, or automatic data sharing. Sharing requires you to copy and send the exported text yourself.

## EULA

This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User Licence Agreement (EULA) found at [Jagex’s EULA](https://legal.jagex.com/docs/terms/eula) (and all terms incorporated into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.

## Feedback and contributions

For questions or discussion, use the [RuneScape Plugin Discord](https://discord.com/invite/uFpDsrNWDQ) or the [Notes+ plugin thread](https://discord.com/channels/1523582684109082645/1561732919989370931).

Use [GitHub Issues](https://github.com/Stitch-P/NotesPlus/issues) to report a bug or suggest an improvement. If a bug needs a note or share code to reproduce it, use sample data.

[Pull requests](https://github.com/Stitch-P/NotesPlus/pulls) are welcome. Open an issue to discuss larger changes and describe how you tested your change. Community changes need one approval from a maintainer before merging.

### Testing in the developer beta

Run these commands in order in the RuneScape developer console.

```text
ppr NotesPlus
ppe NotesPlus chatAccess
ppe NotesPlus trackingAccess
prl NotesPlus
```

## Maintainers

- [Pavy](https://github.com/Stitch-P)
- [Shauny](https://github.com/Shaunyowns)

Thanks to **Fabled** for playtesting, finding bugs, and suggesting improvements.

## Source and rights

The source is available for reference. See [LICENSE](LICENSE) for the copyright notice.
