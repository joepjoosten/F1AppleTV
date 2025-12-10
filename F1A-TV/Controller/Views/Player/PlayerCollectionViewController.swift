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
        
        let playerItem = PlayerItem(contentItem: channelItem, position: self.playerItems.count)
        self.playerItems.append(playerItem)
        
        let itemCount = self.playerItems.count
        
        if itemCount == 1 {
            // First player - just reload
            self.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
            
        } else if itemCount == 2 {
            // Transitioning from 1 to 2 players - need to resize existing player
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.performBatchUpdates({
                self.collectionView.insertItems(at: [IndexPath(item: 1, section: 0)])
                self.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
            }, completion: nil)
            
        } else if itemCount <= 4 {
            // Adding player within 2-4 range - all small players need resizing
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.performBatchUpdates({
                self.collectionView.insertItems(at: [IndexPath(item: playerItem.position, section: 0)])
                // Reload all small players (indices 1 through itemCount-2) since their heights change
                let smallPlayerIndices = (1..<itemCount-1).map { IndexPath(item: $0, section: 0) }
                if !smallPlayerIndices.isEmpty {
                    self.collectionView.reloadItems(at: smallPlayerIndices)
                }
            }, completion: nil)
            
        } else if itemCount == 5 {
            // Transitioning from 4 to 5 players - switching to grid layout
            // Need to reload all existing items
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.performBatchUpdates({
                self.collectionView.insertItems(at: [IndexPath(item: 4, section: 0)])
                let existingIndices = (0..<4).map { IndexPath(item: $0, section: 0) }
                self.collectionView.reloadItems(at: existingIndices)
            }, completion: nil)
            
        } else {
            // Adding more players in grid layout - just insert the new one
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.insertItems(at: [IndexPath(item: playerItem.position, section: 0)])
        }
        
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
    
    /*func didLoadStreamEntitlement(playerId: String, streamEntitlement: StreamEntitlementDto) {
        if let index = self.playerItems.firstIndex(where: {$0.id == playerId}) {
            var playerItem = self.playerItems[index]
            
            playerItem.entitlement = streamEntitlement
            
            //if let url = URL(string: streamEntitlement.url) {
            DataManager.instance.loadM3U8Data(url: streamEntitlement.url, completion: { m3u8Data in
                DispatchQueue.main.async {
                    //print(m3u8Data)
                    //let baseUrlString = streamEntitlement.url.components(separatedBy: "index.m3u8").first ?? ""
                    
                    var m3u8Lines = m3u8Data.components(separatedBy: .newlines)
                    var lineIndex = 0
                    while (lineIndex < m3u8Lines.count) {
                        let currentLine = m3u8Lines[lineIndex]
                        if(currentLine.starts(with: "#EXT-X-STREAM-INF")) {
                            if(!currentLine.contains("RESOLUTION=480x270")){
                                m3u8Lines.remove(at: lineIndex + 1)
                                m3u8Lines.remove(at: lineIndex)
                                
                                continue
                            }
                        }
                        
                        lineIndex += 1
                    }
                    
                    //let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                    //let streamFileUrl = urls[urls.endIndex-1].appendingPathComponent("\(playerItem.id).m3u8")
                    let m3u8Content = m3u8Lines.joined()
                    
                    /*do {
                        try m3u8Content.write(to: streamFileUrl, atomically: true, encoding: String.Encoding.utf8)
                    } catch {
                        print("Couldn't write file")
                    }*/
                    
                    /*if let baseUrl = URL(string: baseUrlString) {
                     let parser = M3U8Parser()
                     let params = M3U8Parser.Params(playlist: m3u8Data, playlistType: .master, baseUrl: baseUrl)
                     
                     do {
                     let playlistResult = try parser.parse(params: params, extraParams: nil)
                     if case let .master(masterPlaylist) = playlistResult {
                     let streamUrl = masterPlaylist.tags.streamTags.first(where: {$0.resolution == "480x270"})?.uri ?? ""
                     
                     if let potatoUrl = URL(string: "\(baseUrlString)\(streamUrl)") {*/
                    
                    let m3u8Server = Server()
                    m3u8Server.route(.GET, playerItem.id, content: {(.ok, m3u8Content)})
                    do {
                        try m3u8Server.start(port: 2506)
                    } catch (let error) {
                        print("Couldn't start server " + error.localizedDescription)
                    }
                    
                    if let localUrl =  URL(string: "http://localhost:2506/\(playerItem.id)") {
                        playerItem.playerAsset = AVAsset(url: localUrl)
                        playerItem.playerItem = AVPlayerItem(asset: playerItem.playerAsset ?? AVAsset())
                        playerItem.player = AVPlayer(playerItem: playerItem.playerItem)
                        playerItem.player?.appliesMediaSelectionCriteriaAutomatically = false
                        
                        self.setPreferredDisplayCriteria(displayCriteria: playerItem.playerAsset?.preferredDisplayCriteria)
                    }
                    /*}
                     }
                     } catch {
                     print("Couldn't parse playlist")
                     }*/
                    
                    /*self.playerItems[index] = playerItem
                     
                     self.collectionView.reloadItems(at: [IndexPath(item: playerItem.position, section: 0)])*/
                    PlayerController.instance.openPlayer(player: playerItem.player ?? AVPlayer())
                    //}
                }
            })
        }
    }*/
    
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
        
        let countBeforeRemoval = self.playerItems.count
        
        self.playerItems.removeAll(where: {$0.id == playerItem.id})
        self.orderChannels()
        
        self.collectionView.collectionViewLayout.invalidateLayout()
        
        let remainingCount = self.playerItems.count
        
        if remainingCount == 0 {
            // No players left - show empty state
            self.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
            
        } else if remainingCount == 1 {
            // Going from 2 to 1 player - reload remaining player to make it full screen
            if removedIndex == 0 {
                // Removed index 0, so reload what was index 1 (now index 0)
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [IndexPath(item: 0, section: 0)])
                    self.collectionView.reloadItems(at: [IndexPath(item: 1, section: 0)])
                }, completion: nil)
            } else {
                // Removed index 1, so reload index 0
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [IndexPath(item: 1, section: 0)])
                    self.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
                }, completion: nil)
            }
            
        } else if countBeforeRemoval >= 2 && countBeforeRemoval <= 4 {
            // Within 2-4 player range
            if removedIndex == 0 {
                // Removed the main player - reload all remaining items (they all shifted down)
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [IndexPath(item: 0, section: 0)])
                    let reloadIndices = (0..<remainingCount).map { IndexPath(item: $0, section: 0) }
                    self.collectionView.reloadItems(at: reloadIndices)
                }, completion: nil)
            } else {
                // Removed a small player (not index 0)
                // All small players need to be reloaded because their heights change
                // AND items after the removed index shift up
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [IndexPath(item: removedIndex, section: 0)])
                    // Reload all small players that existed before deletion (excluding removed one)
                    // AND items that come after the removed index (they shift up)
                    var reloadIndices: [IndexPath] = []
                    for i in 1..<countBeforeRemoval {
                        if i != removedIndex {
                            reloadIndices.append(IndexPath(item: i, section: 0))
                        }
                    }
                    if !reloadIndices.isEmpty {
                        self.collectionView.reloadItems(at: reloadIndices)
                    }
                }, completion: nil)
            }
            
        } else if remainingCount == 4 && countBeforeRemoval == 5 {
            // Going from 5 to 4 players - switching from grid to main+small layout
            self.collectionView.performBatchUpdates({
                self.collectionView.deleteItems(at: [IndexPath(item: removedIndex, section: 0)])
                let reloadIndices = (0..<remainingCount).map { IndexPath(item: $0, section: 0) }
                self.collectionView.reloadItems(at: reloadIndices)
            }, completion: nil)
            
        } else {
            // More than 4 players - staying in grid layout
            if removedIndex == 0 {
                // Removed index 0 - reload all since positions shift
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [IndexPath(item: removedIndex, section: 0)])
                    let reloadIndices = (0..<remainingCount).map { IndexPath(item: $0, section: 0) }
                    self.collectionView.reloadItems(at: reloadIndices)
                }, completion: nil)
            } else {
                // Just delete the removed item
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [IndexPath(item: removedIndex, section: 0)])
                }, completion: nil)
            }
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

// MARK: - Custom Collection View Layout
class PlayerGridLayout: UICollectionViewLayout {
    private var cachedAttributes = [UICollectionViewLayoutAttributes]()
    private var contentSize: CGSize = .zero
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = collectionView else { return }
        
        cachedAttributes.removeAll()
        
        let itemCount = collectionView.numberOfItems(inSection: 0)
        
        guard itemCount > 0 else { return }
        
        let bounds = collectionView.bounds
        let padding: CGFloat = 0
        
        if itemCount == 1 {
            // Single full-screen item
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            attributes.frame = bounds
            cachedAttributes.append(attributes)
            contentSize = bounds.size
            
        } else if itemCount <= 4 {
            // Main player + small players layout
            let mainWidth = floor(bounds.width * 0.666 - padding)
            let mainHeight = bounds.height
            
            let smallWidth = bounds.width - mainWidth
            let smallHeight = bounds.height / CGFloat(itemCount - 1)
            
            // Main player (index 0)
            let mainAttributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            mainAttributes.frame = CGRect(x: 0, y: 0, width: mainWidth, height: mainHeight)
            cachedAttributes.append(mainAttributes)
            
            // Small players (remaining indices)
            for i in 1..<itemCount {
                let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: i, section: 0))
                let yPosition = smallHeight * CGFloat(i - 1)
                let xPosition = mainWidth
                attributes.frame = CGRect(x: xPosition, y: yPosition, width: smallWidth, height: smallHeight)
                cachedAttributes.append(attributes)
            }
            
            contentSize = bounds.size
            
        } else {
            // Grid layout for many players
            let gridSize = CGFloat(itemCount).squareRoot().rounded(.up)
            let itemWidth = bounds.width / gridSize
            let itemHeight = itemWidth / 16 * 9
            
            for i in 0..<itemCount {
                let row = floor(CGFloat(i) / gridSize)
                let col = CGFloat(i).truncatingRemainder(dividingBy: gridSize)
                
                let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: i, section: 0))
                attributes.frame = CGRect(
                    x: itemWidth * col,
                    y: itemHeight * row,
                    width: itemWidth,
                    height: itemHeight
                )
                cachedAttributes.append(attributes)
            }
            
            let rows = ceil(CGFloat(itemCount) / gridSize)
            contentSize = CGSize(
                width: bounds.width,
                height: rows * itemHeight
            )
        }
    }
    
    override var collectionViewContentSize: CGSize {
        return contentSize
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return cachedAttributes.filter { $0.frame.intersects(rect) }
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return cachedAttributes.first { $0.indexPath == indexPath }
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
}
