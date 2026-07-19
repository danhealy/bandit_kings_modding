# Dan's Custom Scenario

A complete rework of **Scenario 2** for *Bandit Kings of Ancient China*.

This mod reshuffles the map, activates every hero in the game, and creates 11 new player-style factions from the original seven starting heroes plus the four strongest non-starting heroes. The result is a much more open, crowded sandbox where nearly every character is on the board at once.

## What changes

### Factions and leaders

The mod promotes the seven original scenario-2 selectable heroes and the four strongest remaining heroes to full faction rulers. Each gets their own prefecture:

| Leader slot | Starting hero | Target prefecture |
|-------------|---------------|-------------------|
| 1 | Lu Zhi Shen | 1 |
| 2 | Shi Jin | 3 |
| 3 | Song Jiang | 6 |
| 4 | Lin Chong | 22 |
| 5 | Wu Song | 34 |
| 6 | Yang Zhi | 48 |
| 7 | Chao Gai | 44 |
| 8 | 4th strongest non-starter | 41 |
| 9 | 3rd strongest non-starter | 40 |
| 10 | 2nd strongest non-starter | 16 |
| 11 | Strongest non-starter | 14 |

Each leader is given **100/80/70** attributes and **100/95/90** personality stats, preserving each hero's natural ordering of strengths. For example, a hero whose highest stat is Wisdom and lowest is Dexterity becomes `Wisdom=100, Strength=80, Dexterity=70`.

### Gao Qiu's stronghold

Gao Qiu (the antagonist) is maxed out with **100** in every attribute and personality, given **100** body, and confined to **prefecture 23** in the center of the map. He also receives **19** powerful recruits, also at 100/80/70 and 100/95/90, making him a serious late-game threat.

### Remaining heroes

Every other hero is activated and distributed evenly, round-robin, among the 11 new factions as unaligned **heroes in town**. The distribution is deterministic (seeded with 42), so the same input always produces the same output.

### Prefectures

- Every prefecture gets a **smithy** and a **shipyard**.
- The 11 new faction prefectures start with **1000 gold**, **1000 food**, and neutral land/flood/wealth values.
- Gao Qiu's prefecture (23) is left as-is except for his own forces moving in.
- All other prefectures are reset to empty neutral defaults with no ruler.

## How to run it

From the project root, run:

```bash
ruby examples/dans_custom_scenario/dans_custom_scenario.rb
```

By default it reads `SUIDATA2.CIM` from the project root and writes `SUIDATA2_NEW.CIM` in this folder. You can override the input and output paths:

```bash
ruby examples/dans_custom_scenario/dans_custom_scenario.rb \
  -i /path/to/your/SUIDATA2.CIM \
  -o /path/to/output/SUIDATA2_NEW.CIM
```

## Installing the result

1. Back up your original `SUIDATA2.CIM` from the game's `Data` folder.
2. Rename the generated `SUIDATA2_NEW.CIM` to `SUIDATA2.CIM`.
3. Copy it into the game's `Data` folder, replacing the original.
4. Start the game and choose **Scenario 2**.

If you are playing on a classic Mac or emulator and the game does not recognize the file, you may need to use **FileTyper** to copy the file type/creator codes from the original `SUIDATA2.CIM` onto the new file. On modern systems the `.CIM` extension is usually enough.

## Design notes

- **Why Scenario 2?** It is the easiest scenario to customize because it already has a clear set of seven playable starting heroes and a well-known map layout.
- **Why the 4 strongest non-starters?** This keeps the scenario fair-ish — the extra leaders are strong enough to be interesting but were not originally chosen as starters, so the map feels fresh without being wildly unbalanced.
- **Why Gao Qiu gets 19 recruits?** He is intended to be the shared end-game pressure. With every other hero already on the board, his boosted stack forces the player to expand before turning inward.
- **Deterministic shuffle:** The round-robin distribution uses a fixed random seed so the scenario is reproducible and easy to test.

## Files in this folder

- `dans_custom_scenario.rb` — the mod script itself.
- `SUIDATA2_NEW.CIM` — the generated custom scenario file (created after you run the script).
- `README.md` — this file.

## Troubleshooting

- **The script says it cannot find `SUIDATA2.CIM`.** Make sure a copy of the original scenario 2 file is in the project root, or pass `-i` with the full path to the file.
- **The output file is exactly the same size as the input.** That is correct. The toolkit validates a 21,122-byte round-trip to ensure no data was accidentally lost.
- **The game crashes on scenario start.** Most likely a leader flag or ruler byte is inconsistent. Restore your backup and make sure you are feeding in an unmodified original `SUIDATA2.CIM`.
- **The game does not see the new file.** On classic Mac you may need to set the file type/creator with FileTyper. On modern Windows/macOS/Linux, make sure the file is named exactly `SUIDATA2.CIM` and is in the game's `Data` folder.
