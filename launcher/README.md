# Windows launcher

`KFCLauncher.cs` is the launcher (WinForms, one file); `build-launcher.ps1` builds it with the C# compiler
that ships with Windows: `.\launcher\build-launcher.ps1 [-Out <folder>]` (default: the repository's `build\`).

The banner and the icon are optional and are not in the repository: they are cut from two screenshots of
your own copy of the game. Put them in `launcher\assets\` (that folder is git-ignored):

- `menu.png`: the main menu.
- `select.png`: the character select (both at any 4:3 size).

Without them the launcher builds with a plain title and the default icon. `banner.png` and `icon.ico` are
generated into `launcher\` and are not committed either.
