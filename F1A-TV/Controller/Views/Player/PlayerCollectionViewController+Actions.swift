//
//  PlayerCollectionViewController+Actions.swift
//  F1A-TV
//
//  Created by Noah Fetz on 29.03.21.
//

import UIKit

// MARK: - Gesture Actions & User Interactions
extension PlayerCollectionViewController {
    
    @objc func playPausePressed() {
        self.reportCurrentPlayTime()
        
        if let firstPlayer = self.playerItems.first {
            if(firstPlayer.player?.timeControlStatus == .paused){
                print("Resuming playback after syncing all channels")
                
                self.syncAllPlayers(with: firstPlayer)
                self.playAll()
            }else{
                print("Pausing playback")
                
                self.pauseAll()
            }
        }
    }
    
    @objc func menuPressed() {
        self.reportCurrentPlayTime()
        
        self.pauseAll()
        self.setPreferredDisplayCriteria(displayCriteria: nil)
        self.dismiss(animated: true)
    }
    
    @objc func swipeUpRegognized() {
        if(self.playerItems.isEmpty || self.lastFocusedPlayer == nil) {
            return
        }
        
        self.showControlStripOverlay()
    }
    
    @objc func swipeLeftRegognized() {
        self.showChannelSelectorOverlay()
    }
    
    @objc func selectLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            self.showChannelSelectorOverlay()
        }
    }
}

// MARK: - Control Strip Actions
extension PlayerCollectionViewController {
    
    func enterFullScreenPlayer() {
        self.reportCurrentPlayTime()
        
        if(self.lastFocusedPlayer == nil) {
            return
        }
        
        let playerItem = self.playerItems[self.lastFocusedPlayer?.item ?? 0]
        self.fullscreenPlayerId = playerItem.id
        
        if let player = playerItem.player {
            self.pauseAll(excludeIds: [playerItem.id])
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PlayerController.instance.openPlayer(player: player, fullscreenPlayerDismissedProtocol: self)
            }
        }
    }
    
    func playPausePlayer() {
        self.reportCurrentPlayTime()
        
        self.playPausePressed()
    }
    
    func rewindPlayer() {
        self.reportCurrentPlayTime()
        
        self.rewindAllPlayersBy(seconds: 15)
    }
    
    func forwardPlayer() {
        self.reportCurrentPlayTime()
        
        self.forwardAllPlayersBy(seconds: 15)
    }
    
    func willCloseFocusedPlayer() {
        self.reportCurrentPlayTime()
        
        if(self.lastFocusedPlayer == nil) {
            return
        }
        
        let removedIndex = self.lastFocusedPlayer?.item ?? 0
        let playerItem = self.playerItems[removedIndex]
        playerItem.player?.pause()
        
        let oldCount = self.playerItems.count
        
        self.playerItems.removeAll(where: {$0.id == playerItem.id})
        self.orderChannels()
        
        let newCount = self.playerItems.count
        
        // Determine update strategy
        let strategy = LayoutUpdateStrategy.determine(
            oldCount: oldCount,
            newCount: newCount,
            oldMainIndex: 0,
            newMainIndex: 0,
            changedIndex: removedIndex
        )
        
        // Apply the layout update
        self.applyLayoutUpdate(strategy: strategy, changedIndex: removedIndex, isAdding: false)
    }
}

// MARK: - Main Player Swapping
extension PlayerCollectionViewController {
    
    func swapMainPlayer(to newIndex: Int) {
        guard newIndex >= 0 && newIndex < self.playerItems.count else { return }
        guard newIndex != 0 else { return } // Already main
        
        if let layout = self.collectionView.collectionViewLayout as? PlayerGridLayout {
            // Store reference to players before swap
            let previousMainPlayer = self.playerItems[0].player
            let newMainPlayer = self.playerItems[newIndex].player
            
            // Swap the player items in the array
            let temp = self.playerItems[0]
            self.playerItems[0] = self.playerItems[newIndex]
            self.playerItems[newIndex] = temp
            self.orderChannels()
            
            // Handle audio: unmute the new main player, mute the previous main player (now in sidebar)
            newMainPlayer?.isMuted = false
            previousMainPlayer?.isMuted = true
            print("Swapped main player: unmuted new main, muted sidebar player")
            
            // Update layout and reload
            layout.mainPlayerIndex = 0  // Main is always at index 0
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.reloadData()
            
            // Sync all players after swap
            if let mainPlayerItem = self.playerItems.first {
                self.syncAllPlayers(with: mainPlayerItem)
            }
        }
    }
    
    func swapToMainPlayer() {
        // Swap the currently focused player to main position
        if let focusedIndex = self.lastFocusedPlayer?.item {
            self.swapMainPlayer(to: focusedIndex)
        }
    }
}
