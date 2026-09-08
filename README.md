# tes_modding

Long-term archive and working memory for Skyrim and Oblivion modlists built in
Mod Organizer 2.

Start with [PLAN.md](PLAN.md).

The modlists live at `X:\MODDING` on a local Windows machine. This repo holds
text snapshots of MO2 state, a changelog, known issues, install research and
decision records. It holds no mod files.

## First time setup on the Windows machine

Clone it next to the installs so local sessions and the export script both find
it without arguments:

```
git clone https://github.com/crypticnull/tes_modding.git X:\MODDING\tes_modding ; powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1 -Root X:\MODDING
```

## Taking a snapshot

To capture the current state of every MO2 instance:

```
powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1 -Root X:\MODDING
```

See [tools/README.md](tools/README.md) for what it reads and writes.
