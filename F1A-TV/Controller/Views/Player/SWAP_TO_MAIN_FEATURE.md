# Swap to Main Player Feature

## Overview
This document describes the implementation of the "Swap to Main" feature, which allows users to swap sidebar or bottom players with the main player in `mainWithSidebar` layout mode. Additionally, sidebar and bottom players are now automatically muted when created.

## Changes Made

### 1. ControlStripActionProtocol.swift
- ✅ Protocol already includes `swapToMainPlayer()` method

### 2. ControlStripOverlayViewController.swift
**Added:**
- New property `swapToMainButton: UIButton?`
- New method `setupSwapToMainButton()` to create the button with swap icon (arrow.up.left.and.arrow.down.right)
- New method `swapToMainPressed()` to handle button tap
- Conditional logic in `addContentToControlsBar()` to only show button for non-main players (position != 0)

**Button Appearance:**
- Normal state: `arrow.up.left.and.arrow.down.right` system icon (outline)
- Focused state: `arrow.up.left.and.arrow.down.right.fill` system icon (filled)
- Position: After "Add Channel" button, before the first spacer
- **Visibility**: Only shown when control strip is opened for sidebar/bottom players (position != 0)
- **tvOS Fix**: Added `layoutIfNeeded()` and `contentMode = .scaleAspectFit` for proper focus highlighting

### 3. PlayerCollectionViewController+Actions.swift
**Enhanced:**
- `swapMainPlayer(to:)` method now handles audio muting/unmuting:
  - Stores references to both players before swap
  - Captures the previous main player's volume
  - After swap: unmutes the new main player and restores volume
  - After swap: mutes the previous main player (now in sidebar) and sets volume to 0
  - Prevents audio bleed from sidebar players
  - Adds debug logging for audio changes

**Existing:**
- `swapToMainPlayer()` method already implemented (calls `swapMainPlayer(to:)` with focused player index)

### 4. PlayerCollectionViewController+PlayerManagement.swift
**Enhanced:**
- `didLoadStreamEntitlement(playerId:streamEntitlement:)` now auto-mutes non-main players:
  - Checks if player index is not 0 (main player)
  - Sets `player.isMuted = true` for sidebar/bottom players
  - Sets `player.volume = 0.0` to ensure no audio leaks through
  - Adds debug logging

- `setPreferredChannelSettings(playerItem:)` now respects player position:
  - Only applies user audio preferences (volume/mute) to main player (position 0)
  - Forces sidebar/bottom players to remain muted with volume at 0
  - Prevents audio settings from being restored on sidebar players after they're ready

## User Experience

### When Opening a Sidebar/Bottom Player:
1. User adds a new channel (not the first one)
2. The player loads in a sidebar or bottom position
3. **Audio is automatically muted** for this player
4. Main player continues playing with audio

### Using the Swap Button:
1. User focuses on a sidebar or bottom player
2. User swipes up to open Control Strip
3. User selects the new "Swap to Main" button (third button from left)
4. **The focused player swaps with the main player**
5. **Audio unmutes on the new main player**
6. **Audio mutes on the previous main (now sidebar) player**
7. All players sync to the main player's time
8. Layout updates to reflect new positions

## Layout Modes
This feature is most relevant in `mainWithSidebar` mode (2-6 players):
- 1 player: Single mode (no swap needed)
- 2-6 players: Main with sidebar/bottom (swap button useful)
- 7+ players: Grid mode (swap button still works but less intuitive)

## Control Strip Button Order
1. Remove Channel (X icon)
2. Add Channel (+ icon)
3. **Swap to Main (swap arrows icon)** ← NEW
4. [Spacer]
5. Rewind
6. Play/Pause
7. Forward
8. [Spacer]
9. Mute
10. Volume Slider
11. Language Selector
12. [Spacer]
13. Fullscreen

## Technical Notes

### Audio Muting Strategy:
- **On Load**: Non-main players (index != 0) are muted and volume set to 0 in `didLoadStreamEntitlement`
- **On Ready**: `setPreferredChannelSettings` checks player position and only applies user audio preferences to main player (position 0)
- **On Swap**: Both `isMuted` and `volume` are updated to prevent audio bleed from sidebar players
- **User Override**: Users can still manually unmute sidebar players via the Control Strip, which will restore their volume

### Synchronization:
- After swapping, all players sync to the new main player's position
- This ensures seamless viewing experience when switching perspectives

### Layout Updates:
- Layout invalidation ensures proper positioning after swap
- Collection view reloads to update cell focus states
- Main player index always remains at 0 (array position)

## Future Enhancements (Optional)
1. Add visual indicator showing which player is main
2. Add double-tap gesture as shortcut to swap without opening Control Strip
3. Consider adding audio ducking instead of full mute for sidebar players
4. Persist user's audio preferences per channel type

## Troubleshooting

### Issue: Sidebar player audio is still audible
**Root Cause**: AVPlayer's `isMuted` property alone may not be sufficient on some systems.

**Solution**: The implementation now uses a dual approach:
1. Sets `isMuted = true` (prevents audio routing)
2. Sets `volume = 0.0` (ensures no audio output)

This happens in three places:
- Initial load (`didLoadStreamEntitlement`)
- When player becomes ready (`setPreferredChannelSettings`)
- When swapping to sidebar (`swapMainPlayer`)

### Issue: Audio preferences not working for main player
**Root Cause**: If you swap a player that had its audio manually adjusted, those settings might be lost.

**Solution**: The swap function captures the previous main player's volume and applies it to the new main player, ensuring consistent audio levels.
