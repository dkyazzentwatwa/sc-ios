# StarCraft Assets Directory

This directory must contain StarCraft: Brood War game files for the iOS port to function.

## ⚠️ Important Legal Notice

**These files are NOT included in this repository.** You must own a legitimate copy of StarCraft: Brood War and provide your own game files.

## Required Files

Place the following MPQ files in this directory:

```
ios/Assets/
├── StarDat.mpq      (~60 MB)  - Main StarCraft data
├── BrooDat.mpq      (~24 MB)  - Brood War expansion data
├── Patch_rt.mpq     (~1 MB)   - Patch files
└── maps/                      - Map files directory
    ├── (2)Boxer.scx
    ├── (2)Lost Temple.scx
    └── ...
```

## Where to Get These Files

### Option 1: Official Purchase
Purchase StarCraft: Remastered from:
- [Battle.net](https://www.blizzard.com/en-us/games/sc) (includes original version)
- Note: As of 2017, the original StarCraft is free-to-play

### Option 2: Existing Installation
If you already have StarCraft installed on your computer, locate the MPQ files:

**Windows:**
```
C:\Program Files (x86)\StarCraft\
```

**macOS:**
```
/Applications/StarCraft/
```

## Supported Versions

- StarCraft: Brood War **1.16.1** (recommended)
- StarCraft: Brood War **1.18+** (also compatible)

## Installation Instructions

### For Development (Simulator)

1. Copy MPQ files to this directory:
```bash
cp /path/to/your/starcraft/*.mpq ./
cp -r /path/to/your/starcraft/maps ./
```

2. When running on simulator, assets are automatically copied to:
```bash
~/Library/Developer/CoreSimulator/Devices/[DEVICE_ID]/data/Containers/Data/Application/[APP_ID]/Documents/
```

### For Device Installation

The app will look for MPQ files in the app's Documents directory. You can:

1. Use Xcode's "Download Container" feature to add files
2. Use iTunes File Sharing (if enabled)
3. Modify the app to download from iCloud/Dropbox

## File Structure

```
ios/Assets/
├── README.md           # This file
├── StarDat.mpq        # ← You must add this
├── BrooDat.mpq        # ← You must add this
├── Patch_rt.mpq       # ← You must add this
└── maps/              # ← You must add this directory
    └── *.scx          # Map files
```

## Troubleshooting

### "Cannot find StarDat.mpq" Error
- Verify files are in the correct location
- Check file names match exactly (case-sensitive on some systems)
- Ensure files are from version 1.16.1 or 1.18

### "MPQ file is corrupted" Error
- Re-download or re-copy the files from your StarCraft installation
- Verify file sizes match expected values
- Check that files aren't compressed or modified

### File Sizes Reference
- `StarDat.mpq`: ~60-61 MB
- `BrooDat.mpq`: ~23-24 MB
- `Patch_rt.mpq`: ~960 KB - 1 MB

## Legal

StarCraft and StarCraft: Brood War are registered trademarks of Blizzard Entertainment, Inc.

This project does not distribute or include any copyrighted Blizzard Entertainment assets. Users must provide their own legally obtained game files.

## Need Help?

- Check the [main README](../../README.md) for setup instructions
- Open an issue on GitHub for technical problems
- **Do NOT** request or share MPQ files - this violates copyright law
