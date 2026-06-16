# Atari ST Disk Image Editor for macOS

A simple, native macOS application to open, browse, modify and extract files from Atari ST disk images. Also allows creating new disk images.

## Features

- Open and browse **.st**, **.msa**, **.dim** and **.ahd** disk images
- Extract, modify and add files inside the disk image
- Create new blank disk images
- Custom disk geometries support
- Native macOS application (Apple Silicon + Intel)

**Note:** You can open `.dim` and `.ahd` files, but saving is currently only supported for `.st` and `.msa` formats.

## Inspired by

- [Krystone DiskTools](https://krystone.pl/st/disktools/)
- [MSA Converter](http://msaconverter.free.fr/index-uk.html)
- [Jacknife](https://github.com/ggnkua/Jacknife)

## Download

**[⬇️ Download AtariFileMgr (macOS)](https://hangloose.climatics.ch/Emulators/AtariFileMgr-Release.dmg?login=atarist:atarist)**

## Source Code

This project is open source. Feel free to contribute!

→ [github.com/BanditCLX/atariFilemgr](https://github.com/BanditCLX/atariFilemgr)

## Version History

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
