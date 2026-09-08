# Decisions log

Every mod that is switched off, removed, or deliberately not installed, and
why. Each entry carries a verdict:

  PERMANENT   proven, closed, do not revisit. Folder goes to `_retired\`.
  DEFERRED    not broken - switched off for a reason that may expire.
  REJECTED    evaluated and not installed. Recorded so it is not re-evaluated.

If something is unchecked in MO2 and is not in this file, that is a bug in the
record, not a decision. Anything PERMANENT should not still be sitting in
`mods\` - retire it.

---

## PERMANENT

### Dynamic Wetness  (Nexus 158207)  -  retired 2026-09-07
Ships `DynamicWetness.dll`, which Community Shaders **hard-blocks by name** in
its plugin block list. CS does not just ignore it: it disables **all** of its
hooks and features and says so in a popup at startup. No CS means no Upscaling
feature, so no DLSS feature is ever created, so the DLSS 5 bridge has nothing
to attach the neural pass to. The symptom was "neural rendering is off", which
is nowhere near the cause, and it cost hours.

Also redundant regardless: `CS - Wetness Effects` does the same job natively
and is already installed.

Closed. Do not reinstall. `nr_check.ps1` now tests for this whole class of DLL.

### Improved Alternate Conversation Camera  (Nexus 68210)  -  retired 2026-09-06
Instant crash at the main menu, exception `0x80000003` (STATUS_BREAKPOINT - a
deliberate abort, not a memory fault) at `SkyrimSE.exe+0xCC5B80`, every launch.

Cause: SmoothCam hands the dialogue camera to a plugin only when that plugin
registers through its messaging interface under the consumer name
`Alternate Conversation Camera`. IACC's own changelog says its SmoothCam
support is *disabled until fixed*, so it never registers, the handoff never
happens, and both DLLs drive the camera on the same frames.

**Both documented fixes were tested and both failed**: setting `bSmoothCam = 1`
in `AlternateConversationCamera.ini`, and setting SmoothCam's `dialogueMode` to
0 (Disabled) so SmoothCam was entirely out of the dialogue camera. Still
crashed instantly with SmoothCam not involved at all.

Closed. SmoothCam's `dialogueMode` has been restored to 1.

Note for anyone tempted to solve this another way: SmoothCam itself contains
`Oblivion` and `FaceToFace` dialogue modes with full framing offsets, but they
are registered inside `#ifdef DEVELOPER` and the build never defines it. The
MCM still lists them; selecting either sets the active mode to null and
silently disables SmoothCam's dialogue handling. There is no DLL-free
alternative either - Papyrus has no camera API, only `SetCameraTarget`, which
changes which actor the camera orbits and cannot frame a shot.

### TAWoBA - CBBE SE 9547  -  retired 2026-09-07
Superseded by TAWOBA Remastered 6.1. The old version ships prebuilt meshes with
**no BodySlide slider sets at all** - 1102 meshes, 1102 uncovered - so it can
never follow an OBody preset. Remastered ships CBBE 3BAv2 natively plus SMP
skirt physics.

Different plugin, so this was a swap, not an upgrade: items from 9547 are gone
from any save that had them.

### ReSqueeze - TAWOBA 3BA  (Nexus 131355)  -  retired 2026-09-07
Built for TAWoBA 9547, which is gone. It did work - it covered 73 of 1102
meshes, which is how we confirmed it targeted 9547 rather than Remastered - but
it is pointless now.

---

## DEFERRED

### Northern Roads  (Nexus 77530)  -  disabled 2026-09-06
Not broken. Disabled because of a terrain seam at Whiterun's front gate - the
dirt sat below the gate floor, producing a stone ledge you had to jump.

**This one may come back.** Several PBR landscape packs pair with Northern
Roads or Blended Roads, and the chosen pack matters: Vanaheimr **includes
Blended Roads**, so it does not need Northern Roads back. If the landscape
choice changes, revisit this.

Still in `mods\`, deliberately, because it is not dead.

---

## REJECTED - evaluated, not installed

### Bikini Armor Replacer (TAWOBA) - CBBE BodySlide  (Nexus 40015)
Would have covered the ~1029 TAWoBA 9547 meshes ReSqueeze did not, making the
whole set follow OBody. Rejected because it is a **CBBE-reference** conversion:
it builds meshes weighted to CBBE bones, not 3BA ones. On armour that is mostly
skin, that trades a shape mismatch for rigid geometry - worse, not better.
Moot now that Remastered ships native 3BAv2.

### Vyrthland - Landscapes AIO  (Nexus 190416)  -  revisit ~Oct 2026
Probably the better-looking PBR landscape pack, and less risky than "v1.0, four
days old" sounds - it is built on Cl3mus's Vanaheimr meshes and ESP framework
with his active help. Rejected **for now** on: three hard requirements not
installed (Better Dynamic Snow, Icy Mesh Remaster, Enhanced Rocks and
Mountains), ~45 endorsements and an empty bug tracker, an acknowledged and
deferred road-seam defect, 2.3x the size at 1K, and daily updates - each of
which would force a PGPatcher rerun plus a DynDOLOD regeneration.

Revisit when its bug tracker has content and the road seams are addressed.

### Animation stack phase two - OAR, Pandora, Goetia, ABF
Deprioritised, not rejected. The actual complaint - the casting arm dropping
while moving - was **XPMSE with no skeleton behaviour patch**, fixed by
`Auto Skeleton Patch` (176724) alone, no behaviour engine required. The rest of
the stack buys procedural leaning, 360 mounted archery and better casting
animations, none of which are problems today.

---

## PENDING REMOVAL - scheduled, not yet done

### Simplicity of Snow  (Nexus 56235)
Must come out **before PBR**. Double-pass snow shaders do not work with PBR
textures, and it is called out as incompatible by the landscape packs. Better
Dynamic Snow 3 replaces it and is a prerequisite for most of them anyway.

### MajesticMountains_Moss.esp
Only if a Majestic Mountains PBR conversion is used - double-pass moss shaders
have the same problem as the snow ones. Both MM PBR conversions document its
removal as required.

---

## Settings decisions, for completeness

| Setting | Value | Why |
|---|---|---|
| `dlss5-bridge.cfg` `skip_game` | `0` | `1` hands the temporal resolve to the bridge's D3D12 mirror. Distance shimmer, present even with the neural add-on removed. |
| `dlss5-bridge.cfg` `reset_every` | `0` | It applies the NGX **Reset** flag, wiping DLSS history. Documented as diagnostic only. The old value of 600 was inference, and wrong. |
| `SSEDisplayTweaks.ini` `FramerateLimit` | `60` | CPU-bound at ~78 fps averaging 77 C and 89 W. The frame rate is the CPU work rate here. Havok clamp stays on regardless. |
| SmoothCam `dialogueMode` | `1` | Restored after the IACC test failed. |
| OBody ORefit | TAWoBA blacklisted | Testing whether ORefit is what makes the bikini straps read as loose. Costs no rebuild. |
