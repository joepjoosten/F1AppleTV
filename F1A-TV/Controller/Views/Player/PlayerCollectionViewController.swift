//
//  PlayerCollectionViewController.swift
//  F1A-TV
//
//  Created by Noah Fetz on 29.03.21.
//

import UIKit
import AVKit
//import Telegraph

class PlayerCollectionViewController: BaseCollectionViewController, StreamEntitlementLoadedProtocol, ChannelSelectionProtocol, ControlStripActionProtocol, FullscreenPlayerDismissedProtocol, PlayTimeReportedProtocol {
    var channelItems = [ContentItem]()
    var playerItems = [PlayerItem]()
    var lastFocusedPlayer: IndexPath?
    
    var fullscreenPlayerId: String?
    
    var playerInfoViewController: PlayerInfoOverlayViewController?
    var channelSelectorViewController: ChannelSelectorOverlayViewController?
    var controlStripViewController: ControlStripOverlayViewController?
    
    var isFirstPlayer = true
    var playFromStart = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupCollectionView()
    }
    
    func setupCollectionView() {
        self.collectionView.backgroundColor = .black
        
        // Use custom layout for main + small players arrangement
        let customLayout = PlayerGridLayout()
        self.collectionView.collectionViewLayout = customLayout
        
        let playPauseGesture = UITapGestureRecognizer(target: self, action: #selector(self.playPausePressed))
        playPauseGesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        self.collectionView.addGestureRecognizer(playPauseGesture)
        
        //Override the default menu back because we need to stop all players before we dismiss the view controller
        let menuGesture = UITapGestureRecognizer(target: self, action: #selector(self.menuPressed))
        menuGesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        self.collectionView.addGestureRecognizer(menuGesture)
        
//        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.panGesturePerformed))
//        self.collectionView.addGestureRecognizer(panGestureRecognizer)
        
//        let swipeDownRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(self.swipeDownRecognized))
//        swipeDownRecognizer.direction = .down
//        self.collectionView.addGestureRecognizer(swipeDownRecognizer)

        let swipeUpRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(self.swipeUpRegognized))
        swipeUpRecognizer.direction = .up
        self.collectionView.addGestureRecognizer(swipeUpRecognizer)

        let swipeLeftRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(self.swipeLeftRegognized))
        swipeLeftRecognizer.direction = .left
        self.collectionView.addGestureRecognizer(swipeLeftRecognizer)
        
        // Add select button (long press) gesture to show channel selector (useful in simulator)
        let selectLongPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(self.selectLongPressed))
        selectLongPressGesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        self.collectionView.addGestureRecognizer(selectLongPressGesture)
    }
    
    func initialize(channelItems: [ContentItem], playFromStart: Bool? = false) {
        self.channelItems = channelItems
        self.playFromStart = playFromStart ?? false
        
        for mainChannel in self.channelItems.filter({$0.container.metadata?.channelType == .MainFeed}) {
            self.loadStreamEntitlement(channelItem: mainChannel)
        }
    }
    
    func loadStreamEntitlement(channelItem: ContentItem) {
        self.orderChannels()
        
        let oldCount = self.playerItems.count
        
        let playerItem = PlayerItem(contentItem: channelItem, position: self.playerItems.count)
        self.playerItems.append(playerItem)
        self.orderChannels()
        
        let newCount = self.playerItems.count
        
        // Determine update strategy
        let strategy = LayoutUpdateStrategy.determine(
            oldCount: oldCount,
            newCount: newCount,
            oldMainIndex: 0,
            newMainIndex: 0,
            changedIndex: newCount - 1
        )
        
        // Apply the layout update
        self.applyLayoutUpdate(strategy: strategy, changedIndex: newCount - 1, isAdding: true)
        
        if let id = channelItem.container.metadata?.contentId {
            if let additionalStream = channelItem.container.metadata?.additionalStreams?.first {
                
                
                self.loadStreamEntitlement(playerId: playerItem.id, contentId: additionalStream.playbackUrl)
                return
            }
            
            self.loadStreamEntitlement(playerId: playerItem.id, contentId: String(id))
        }
    }
    
    func loadStreamEntitlement(playerId: String, contentId: String) {
        var contentUrl = contentId
        if(!contentUrl.starts(with: "CONTENT")){
            contentUrl = "CONTENT/PLAY?contentId=" + contentId
        }
        DataManager.instance.loadStreamEntitlement(contentId: contentUrl, playerId: playerId, streamEntitlementLoadedProtocol: self)
    }
    
    func didLoadStreamEntitlement(playerId: String, streamEntitlement: StreamEntitlementDto) {
        if let index = self.playerItems.firstIndex(where: {$0.id == playerId}) {
            var playerItem = self.playerItems[index]
            
            playerItem.entitlement = streamEntitlement
            
            playerItem.player = FairPlayer()
            playerItem.player?.playStream(streamEntitlement: streamEntitlement)
            playerItem.playerAsset = playerItem.player?.makeFairPlayReady()
            playerItem.playerItem = AVPlayerItem(asset: playerItem.playerAsset ?? AVAsset())
            playerItem.player?.replaceCurrentItem(with: playerItem.playerItem)
            playerItem.player?.appliesMediaSelectionCriteriaAutomatically = false
            
            if(self.playFromStart) {
                playerItem.player?.seek(to: CMTimeMakeWithSeconds(Float64(1), preferredTimescale: 1))
                self.playFromStart = false
            }
            
            self.setPreferredDisplayCriteria(displayCriteria: playerItem.playerAsset?.preferredDisplayCriteria)
            
            self.playerItems[index] = playerItem
            
            self.collectionView.reloadItems(at: [IndexPath(item: playerItem.position, section: 0)])
        }
    }
    
    func fullscreenPlayerDidDismiss() {
        if let syncPlayerItem = self.playerItems.first(where: {$0.id == self.fullscreenPlayerId}) {
            self.syncAllPlayers(with: syncPlayerItem)
            self.setPreferredDisplayCriteria(displayCriteria: syncPlayerItem.playerAsset?.preferredDisplayCriteria)
        }else{
            self.playAll()
        }
    }
    
    func didSelectChannel(channelItem: ContentItem) {
        self.loadStreamEntitlement(channelItem: channelItem)
    }
    
    // MARK: UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if(self.playerItems.isEmpty) {
            return 1
        }
        return self.playerItems.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if(self.playerItems.isEmpty) {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ConstantsUtil.noContentCollectionViewCell, for: indexPath) as! NoContentCollectionViewCell
            
            cell.centerLabel.text = "multiplayer_no_channels_add_first".localizedString
            
            return cell
        }
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ConstantsUtil.channelPlayerCollectionViewCell, for: indexPath) as! ChannelPlayerCollectionViewCell
        
        cell.loadingSpinner?.startAnimating()
        
        let currentItem = self.playerItems[indexPath.item]
        
        cell.titleLabel.text = ""
        cell.subtitleLabel.text = ""
        cell.subtitleLabel.textColor = .white
        
        switch currentItem.contentItem.container.metadata?.channelType {
        case .MainFeed, .AdditionalFeed:
            cell.titleLabel.text = currentItem.contentItem.container.metadata?.title
            
        case .OnBoardCamera:
            cell.titleLabel.text = currentItem.contentItem.container.metadata?.title
            
            if let additionalStream = currentItem.contentItem.container.metadata?.additionalStreams?.first {
                cell.subtitleLabel.text = additionalStream.teamName
                cell.subtitleLabel.textColor = UIColor(rgb: additionalStream.hex ?? "#00000000")
            }
            
        default:
            print("Shouldn't happen (Hopefully ^^)")
        }
        
        if let player = currentItem.player {
            cell.startPlayer(player: player)
            player.play()
            
            cell.loadingSpinner?.stopAnimating()
            
            self.waitForPlayerReadyToPlay(playerItem: currentItem)
        }
        
        return cell
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if(self.playerItems.isEmpty) {
            self.showChannelSelectorOverlay()
            return
        }
        
        self.showControlStripOverlay()
    }
    
    override func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        if collectionView == self.collectionView {
            if(self.playerItems.isEmpty){
                self.lastFocusedPlayer = nil
                return
            }
            
            if let nextFocusedIndexPath = context.nextFocusedIndexPath {
                self.lastFocusedPlayer = nextFocusedIndexPath
                return
            }
            
            if let previouslyFocusedIndexPath = context.previouslyFocusedIndexPath {
                self.lastFocusedPlayer = previouslyFocusedIndexPath
                return
            }
        }
    }
    
    func waitForPlayerReadyToPlay(playerItem: PlayerItem){
        if let player = playerItem.player {
            DispatchQueue.global().async {
                var tryCount = 0
                while(player.status != .readyToPlay) {
                    if(tryCount >= 240) { //Wait max 1 min before aborting
                        print("Took more than 1 min to load, aborting...")
                        return
                    }
                    tryCount += 1
                    
                    print("Waiting for ready to play for " + String(tryCount) + " times")
                    usleep(250000)
                }
                print("Now ready to play")
                usleep(500000)
                
                self.setPreferredChannelSettings(playerItem: playerItem)
                
                if let resumePlayHeadPosition = playerItem.contentItem.container.user?.resume?.playHeadPosition, self.isFirstPlayer {
                    self.seekAllPlayersTo(time: Float64(resumePlayHeadPosition))
                    self.isFirstPlayer = false
                }else{
                    self.syncAllPlayers(with: self.playerItems.first ?? PlayerItem())
                }
            }
        }
    }
    
    func setPreferredChannelSettings(playerItem: PlayerItem) {
        let playerSettings = CredentialHelper.getPlayerSettings()
        let channelType = playerItem.contentItem.container.metadata?.channelType ?? ChannelType()
        
        if let preferredLanguage = playerSettings.getPreferredLanguage(for: channelType) {
            let setLanguageResult = playerItem.playerItem?.select(type: .audio, languageDisplayName: preferredLanguage)
            print("Setting preferred language: " + String(setLanguageResult ?? false))
        }

        if let preferredCaptions = playerSettings.getPreferredCaptions(for: channelType) {
            let setCaptionResult = playerItem.playerItem?.select(type: .subtitle, languageDisplayName: preferredCaptions)
            print("Setting preferred caption: " + String(setCaptionResult ?? false))
        }
        
        playerItem.player?.volume = playerSettings.getPreferredVolume(for: channelType)
        playerItem.player?.isMuted = playerSettings.getPreferredMute(for: channelType)
    }
    
    /*@objc func panGesturePerformed(_ panGesture: UIPanGestureRecognizer) {
        let translation = panGesture.translation(in: self.collectionView)
        let velocity = panGesture.velocity(in: self.collectionView)
        
        if(abs(translation.x) > 150 && abs(velocity.x) > 8000) {
            print("Horizontal Pan gesture performed: translation x -> \(translation.x), velocity -> \(velocity.x)")
            panGesture.isEnabled = false
            panGesture.isEnabled = true
            
            if(translation.x < 0){
                self.showChannelSelectorOverlay()
            }
            
            return
        }
        
        if(abs(translation.y) > 150 && abs(velocity.y) > 8000) {
            print("Vertical Pan gesture performed: translation y -> \(translation.y), velocity -> \(velocity.y)")
            panGesture.isEnabled = false
            panGesture.isEnabled = true
            
//            self.showChannelSelectorOverlay()
            
            return
        }
    }*/
    
//    @objc func swipeDownRecognized() {
//        self.showInfoOverlay()
//    }
    
    func showInfoOverlay() {
        if(self.playerInfoViewController == nil) {
            self.playerInfoViewController = self.getViewControllerWith(viewIdentifier: ConstantsUtil.playerInfoOverlayViewController) as? PlayerInfoOverlayViewController
            self.playerInfoViewController?.modalPresentationStyle = .overCurrentContext
            self.playerInfoViewController?.initialize(contentItem: self.channelItems.first(where: {$0.container.metadata?.channelType == .MainFeed}) ?? ContentItem())
        }
        
        if(self.playerInfoViewController?.isBeingPresented ?? true) {
            return
        }
        
        self.present(self.playerInfoViewController ?? UIViewController(), animated: true)
    }
    
    @objc func swipeUpRegognized() {
        if(self.playerItems.isEmpty || self.lastFocusedPlayer == nil) {
            return
        }
        
        self.showControlStripOverlay()
    }
    
    func showControlStripOverlay() {
        self.controlStripViewController = self.getViewControllerWith(viewIdentifier: ConstantsUtil.controlStripOverlayViewController) as? ControlStripOverlayViewController
        self.controlStripViewController?.modalPresentationStyle = .overCurrentContext
        
        let focusedPlayerItem = self.playerItems[self.lastFocusedPlayer?.item ?? 0]
        
        self.controlStripViewController?.initialize(playerItem: focusedPlayerItem, controlStripActionProtocol: self)
        
        if(self.controlStripViewController?.isBeingPresented ?? true) {
            return
        }
        
        self.present(self.controlStripViewController ?? UIViewController(), animated: true)
    }
    
    @objc func swipeLeftRegognized() {
        self.showChannelSelectorOverlay()
    }
    
    @objc func selectLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            self.showChannelSelectorOverlay()
        }
    }
    
    func showChannelSelectorOverlay() {
        if(self.channelSelectorViewController == nil) {
            self.channelSelectorViewController = self.getViewControllerWith(viewIdentifier: ConstantsUtil.channelSelectorOverlayViewController) as? ChannelSelectorOverlayViewController
            self.channelSelectorViewController?.modalPresentationStyle = .overCurrentContext
            self.channelSelectorViewController?.initialize(channelItems: self.channelItems, selectionReturnProtocol: self)
        }
        
        if(self.channelSelectorViewController?.isBeingPresented ?? true) {
            return
        }
        
        self.present(self.channelSelectorViewController ?? UIViewController(), animated: true)
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
    
    // MARK: - Layout Update Helper
    func applyLayoutUpdate(strategy: LayoutUpdateStrategy, changedIndex: Int, isAdding: Bool) {
        self.collectionView.collectionViewLayout.invalidateLayout()
        
        switch strategy {
        case .reloadAll:
            // Complete reload - safest option for mode changes
            self.collectionView.reloadData()
            
        case .simpleInsert(let index):
            self.collectionView.insertItems(at: [IndexPath(item: index, section: 0)])
            
        case .simpleDelete(let index):
            self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
            
        case .reloadMainArea, .reloadSidebarOnly:
            // For now, just reload all - can optimize later
            self.collectionView.reloadData()
        }
    }
    
    // MARK: - Main Player Swapping
    func swapMainPlayer(to newIndex: Int) {
        guard newIndex >= 0 && newIndex < self.playerItems.count else { return }
        guard newIndex != 0 else { return } // Already main
        
        if let layout = self.collectionView.collectionViewLayout as? PlayerGridLayout {
            // Swap the player items in the array
            let temp = self.playerItems[0]
            self.playerItems[0] = self.playerItems[newIndex]
            self.playerItems[newIndex] = temp
            self.orderChannels()
            
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
    
    func syncAllPlayers(with syncPlayerItem: PlayerItem) {
        DispatchQueue.main.async {
            print("Syncing all channels")
            
            if let currentTime = syncPlayerItem.player?.currentTime() {
                var syncTime = CMTimeGetSeconds(currentTime)
                
                for playerItem in self.playerItems {
                    if(playerItem.id == syncPlayerItem.id){
                        continue
                    }
                    
                    if let player = playerItem.player, let duration = player.currentItem?.duration {
                        if syncTime >= CMTimeGetSeconds(duration) {
                            syncTime = CMTimeGetSeconds(duration)
                        }
                        player.seek(to: CMTime(value: CMTimeValue(syncTime * 1000), timescale: 1000))
                        
                        if(player.timeControlStatus == .paused) {
                            player.play()
                        }
                    }
                }
            }
            
            if(syncPlayerItem.player?.timeControlStatus == .paused) {
                syncPlayerItem.player?.play()
            }
        }
    }
    
    func forwardAllPlayersBy(seconds: Float64) {
        let syncPlayerItem = self.playerItems.first
        
        if let currentTime = syncPlayerItem?.player?.currentTime() {
            let syncTime = CMTimeGetSeconds(currentTime) + seconds
            self.seekAllPlayersTo(time: syncTime)
        }
    }
    
    func rewindAllPlayersBy(seconds: Float64) {
        let syncPlayerItem = self.playerItems.first
        
        if let currentTime = syncPlayerItem?.player?.currentTime() {
            let syncTime = CMTimeGetSeconds(currentTime) - seconds
            self.seekAllPlayersTo(time: syncTime)
        }
    }
    
    func seekAllPlayersTo(time: Float64) {
        DispatchQueue.main.async {
            var syncTime = time
            
            for playerItem in self.playerItems {
                if let player = playerItem.player, let duration = player.currentItem?.duration {
                    if syncTime >= CMTimeGetSeconds(duration) {
                        syncTime = CMTimeGetSeconds(duration)
                    }
                    player.seek(to: CMTime(value: CMTimeValue(syncTime * 1000), timescale: 1000))
                }
            }
        }
    }
    
    func pauseAll(excludeIds: [String]? = [String]()) {
        DispatchQueue.main.async {
            for playerItem in self.playerItems {
                if((excludeIds?.contains(playerItem.id) ?? false)){
                    continue
                }
                
                if let player = playerItem.player {
                    player.pause()
                }
            }
        }
    }
    
    func playAll(excludeIds: [String]? = [String]()) {
        DispatchQueue.main.async {
            for playerItem in self.playerItems {
                if((excludeIds?.contains(playerItem.id) ?? false)){
                    continue
                }
                
                if let player = playerItem.player {
                    player.play()
                }
            }
        }
    }
    
    func orderChannels() {
        if(self.playerItems.isEmpty) {
            return
        }
        
        for positionIndex in 0...self.playerItems.count-1 {
            self.playerItems[positionIndex].position = positionIndex
        }
    }
    
    func setPreferredDisplayCriteria(displayCriteria: AVDisplayCriteria?) {
        let displayNamager = UserInteractionHelper.instance.getKeyWindow().avDisplayManager
        displayNamager.preferredDisplayCriteria = displayCriteria
    }
    
    func reportCurrentPlayTime() {
        if let firstItem = self.playerItems.first ,let contentId = firstItem.contentItem.container.contentId, let contentSubType = firstItem.contentItem.container.metadata?.contentSubtype, let playerDuration = firstItem.player?.currentTime() {
            DataManager.instance.reportContentPlayTime(reportingItem: PlayTimeReportingDto(contentId: contentId, contentSubType: contentSubType, playHeadPosition: Int(CMTimeGetSeconds(playerDuration)), timestamp: Int(Date().timeIntervalSince1970)), playTimeReportingProtocol: self)
        }
    }
    
    func didReportPlayTime() {
        print("Successfully reported current play time")
    }
}

// MARK: - Layout Manager Types

enum PlayerLayoutMode {
    case single           // 1 player
    case mainWithSidebar  // 2-6 players
    case grid             // 7+ players
    
    static func mode(for playerCount: Int) -> PlayerLayoutMode {
        switch playerCount {
        case 0, 1:
            return .single
        case 2...6:
            return .mainWithSidebar
        default:
            return .grid
        }
    }
}

struct PlayerLayoutConfiguration {
    // Layout constants
    static let mainToSidebarRatio: CGFloat = 0.666  // Main player takes 2/3 width
    static let mainToBottomRatio: CGFloat = 0.666    // Main player takes 2/3 height when bottom row exists
    
    let playerCount: Int
    let mainPlayerIndex: Int
    let bounds: CGRect
    
    var mode: PlayerLayoutMode {
        return PlayerLayoutMode.mode(for: playerCount)
    }
    
    init(playerCount: Int, mainPlayerIndex: Int = 0, bounds: CGRect) {
        self.playerCount = playerCount
        self.mainPlayerIndex = mainPlayerIndex
        self.bounds = bounds
    }
    
    func frame(for index: Int) -> CGRect {
        switch mode {
        case .single:
            return bounds
            
        case .mainWithSidebar:
            return frameMainWithSidebar(for: index)
            
        case .grid:
            return frameGrid(for: index)
        }
    }
    
    private func frameMainWithSidebar(for index: Int) -> CGRect {
        let mainWidth = floor(bounds.width * Self.mainToSidebarRatio)
        let sidebarWidth = bounds.width - mainWidth
        
        let sidebarCount = min(playerCount - 1, 3)
        let bottomCount = max(0, playerCount - 4)
        
        if index == mainPlayerIndex {
            let mainHeight = bottomCount > 0 ? bounds.height * Self.mainToBottomRatio : bounds.height
            return CGRect(x: 0, y: 0, width: mainWidth, height: mainHeight)
        }
        
        let adjustedIndex = index > mainPlayerIndex ? index - 1 : index
        
        if adjustedIndex < sidebarCount {
            let sidebarHeight = bounds.height / CGFloat(sidebarCount)
            let y = sidebarHeight * CGFloat(adjustedIndex)
            return CGRect(x: mainWidth, y: y, width: sidebarWidth, height: sidebarHeight)
        } else {
            let bottomIndex = adjustedIndex - sidebarCount
            let bottomY = bounds.height * Self.mainToBottomRatio
            let bottomHeight = bounds.height * (1.0 - Self.mainToBottomRatio)
            let bottomWidth = mainWidth / CGFloat(bottomCount)
            let x = bottomWidth * CGFloat(bottomIndex)
            return CGRect(x: x, y: bottomY, width: bottomWidth, height: bottomHeight)
        }
    }
    
    private func frameGrid(for index: Int) -> CGRect {
        let gridSize = ceil(sqrt(CGFloat(playerCount)))
        let itemWidth = bounds.width / gridSize
        let itemHeight = itemWidth / 16 * 9
        
        let row = floor(CGFloat(index) / gridSize)
        let col = CGFloat(index).truncatingRemainder(dividingBy: gridSize)
        
        return CGRect(
            x: itemWidth * col,
            y: itemHeight * row,
            width: itemWidth,
            height: itemHeight
        )
    }
    
    var contentSize: CGSize {
        switch mode {
        case .single, .mainWithSidebar:
            return bounds.size
            
        case .grid:
            let gridSize = ceil(sqrt(CGFloat(playerCount)))
            let itemWidth = bounds.width / gridSize
            let itemHeight = itemWidth / 16 * 9
            let rows = ceil(CGFloat(playerCount) / gridSize)
            return CGSize(width: bounds.width, height: rows * itemHeight)
        }
    }
}

enum LayoutUpdateStrategy {
    case reloadAll
    case reloadMainArea
    case reloadSidebarOnly
    case simpleInsert(at: Int)
    case simpleDelete(at: Int)
    
    static func determine(
        oldCount: Int,
        newCount: Int,
        oldMainIndex: Int,
        newMainIndex: Int,
        changedIndex: Int
    ) -> LayoutUpdateStrategy {
        
        let oldMode = PlayerLayoutMode.mode(for: oldCount)
        let newMode = PlayerLayoutMode.mode(for: newCount)
        
        if oldMode != newMode {
            return .reloadAll
        }
        
        if oldMainIndex != newMainIndex {
            return .reloadAll
        }
        
        if newMode == .grid && changedIndex != 0 {
            return newCount > oldCount ? .simpleInsert(at: changedIndex) : .simpleDelete(at: changedIndex)
        }
        
        if newMode == .mainWithSidebar {
            return .reloadAll
        }
        
        return .reloadAll
    }
}

class PlayerLayoutManager {
    private(set) var configuration: PlayerLayoutConfiguration
    
    init(configuration: PlayerLayoutConfiguration) {
        self.configuration = configuration
    }
    
    func layoutAttributes(for indexPath: IndexPath) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = configuration.frame(for: indexPath.item)
        return attributes
    }
    
    func allLayoutAttributes() -> [UICollectionViewLayoutAttributes] {
        return (0..<configuration.playerCount).map { index in
            layoutAttributes(for: IndexPath(item: index, section: 0))
        }
    }
}

// MARK: - Custom Collection View Layout
class PlayerGridLayout: UICollectionViewLayout {
    private var layoutManager: PlayerLayoutManager?
    var mainPlayerIndex: Int = 0
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = collectionView else { return }
        
        let itemCount = collectionView.numberOfItems(inSection: 0)
        
        let config = PlayerLayoutConfiguration(
            playerCount: itemCount,
            mainPlayerIndex: mainPlayerIndex,
            bounds: collectionView.bounds
        )
        
        layoutManager = PlayerLayoutManager(configuration: config)
    }
    
    override var collectionViewContentSize: CGSize {
        return layoutManager?.configuration.contentSize ?? .zero
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return layoutManager?.allLayoutAttributes().filter { $0.frame.intersects(rect) }
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return layoutManager?.layoutAttributes(for: indexPath)
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
}
