# Atari ST Disk Image Editor for macOS

A simple, native macOS application to open, browse, modify and extract files from Atari ST disk images. Also allows creating new disk images.

## Features

- Open and browse **.st**, **.msa**, **.stx**, **.dim** and **.ahd** disk images
- Extract, modify and add files inside the disk image
- Create new blank disk images
- Custom disk geometries support
- Native macOS application (Apple Silicon + Intel)
- Show and recover/download deleted files from GEMDOS/FAT12 directory entries with automatic Pack-Ice decompression support
- View physical disk layout parameters, space utilization, and interactive cluster allocation map
- Edit OEM ID, make disks bootable, and install standard 68000 executable boot loaders
- Integrated Hex Editor/Viewer with binary chunk carving extractor

**Note:** You can open `.stx` `.dim` and `.ahd` files, but saving is currently only supported for `.st` and `.msa` formats.

## Inspired by

- [Krystone DiskTools](https://krystone.pl/st/disktools/)
- [MSA Converter](http://msaconverter.free.fr/index-uk.html)
- [Jacknife](https://github.com/ggnkua/Jacknife)
- [Atari ST Image GEM Converter / Viewers](https://flab.se/ataristimagegem/)

## Download

**[⬇️ Download AtariFileMgr (macOS)](https://hangloose.climatics.ch/Emulators/AtariFileMgr-Release.dmg?login=atarist:atarist)**

## Source Code

This project is open source. Feel free to contribute!

→ [github.com/BanditCLX/atariFilemgr](https://github.com/BanditCLX/atariFilemgr)

## Version History

**Version 1.8**
- Add `.me` to the list of viewable text files and assign document icons
- Add executable formats (`.prg`, `.tos`, `.ttp`, `.acc`) to the file viewer
- Add Text View Format selector to the text viewer with three options:
  - **RAW TEXT**: Warns when trying to read a binary executable or data block
  - **ASCII CLEANED**: Filters out non-printable binary garbage, leaving only clean text
  - **FIND STRINGS**: Extracts contiguous ASCII sequences of length 4 or more
- Remove "Palette Colors" grid from the graphic viewer footer

**Version 1.7**
- Add third pane: Physical Layout Info (OEM ID modifier, boot parameters, executable boot loaders)
- Add interactive Cluster Allocation Map highlighting selected files' clusters
- Add integrated Hex Editor/Viewer (offset, hex bytes, ASCII table) with copy features
- Add segment-based Binary Chunk Carving/Extractor to save custom offset ranges to macOS

**Version 1.6**
- Add deleted file recovery feature (with contiguous cluster carving from GEMDOS/FAT12 directory records)
- Allow browsing and downloading/saving deleted files to the host macOS system
- Integrate automatic decompression (analog to the depack function) for Pack-Ice compressed files during recovery

**Version 1.5**
- Add Atari ST compression and executable packer detection (Pack-Ice, Atomik, Rob Northen, StoneCracker, etc.)
- Parse archive structures of LZH/LHA, ARC, and ZIP files to list contained files in popover tooltips
- Expose extraction and download options with native decrunching support for Pack-Ice files

**Version 1.4**
- Add option to save viewed images directly to `.png` files via native Save dialog

**Version 1.3**
- Add Atari ST Graphics Viewer supporting DEGAS (`.PI1`-`.PI3`, `.PC1`-`.PC3`), NEOchrome (`.NEO`), STAD (`.PAC`), and Spectrum 512 (`.SPU`) formats
- Add ASCII text file viewer for source code (`.c`, `.h`, `.asm`, `.pas`, `.bas`, etc.) and documentation formats
- Double-click to view files directly, and eye-icon view buttons on toolbars

**Version 1.2**
- Add read-only support for Pasti `.stx` disk images
- Add native Swift Pack-Ice decompressor to transparently decrunch image and text files

**Version 1.1**
- Aligned split view layout and header dividers dynamically
- Standardized vertical height of macOS and Atari ST path navigation bars
- Set consistent heights for file pane action buttons

**Version 1.0** (Initial Release)
- Improved language handling and disk geometry detection
- Added support for `.dim` and `.ahd` files (read support only)
- Custom disk geometry support
- Native support for Intel and Apple Silicon CPUs

---

Made by **Bandit / CLiMATiCS**  
[www.climatics.ch](https://www.climatics.ch)
