
final class ServerDisplay {

	private let prMenuController = NSWindowController(windowNibName:"MenuWindow")
	private let issuesMenuController = NSWindowController(windowNibName:"MenuWindow")

	let prMenu: MenuWindow
	let issuesMenu: MenuWindow
	let apiServerId: NSManagedObjectID?

	var prFilterTimer: PopTimer!
	var issuesFilterTimer: PopTimer!

	init(apiServer: ApiServer?, delegate: NSWindowDelegate) {
		apiServerId = apiServer?.objectID

		prMenu = prMenuController.window as! MenuWindow
		prMenu.itemDelegate = ItemDelegate(type: "PullRequest", sections: Section.prMenuTitles, removeButtonsInSections: [Section.Merged.prMenuName(), Section.Closed.prMenuName()], apiServer: apiServer)
		prMenu.delegate = delegate

		issuesMenu = issuesMenuController.window as! MenuWindow
		issuesMenu.itemDelegate = ItemDelegate(type: "Issue", sections: Section.issueMenuTitles, removeButtonsInSections: [Section.Closed.issuesMenuName()], apiServer: apiServer)
		issuesMenu.delegate = delegate
	}

	func throwAway() {
		prMenu.hideStatusItem()
		prMenu.close()
		issuesMenu.hideStatusItem()
		issuesMenu.close()
	}

	func setTimers() {
		prFilterTimer = PopTimer(timeInterval: 0.2) { [weak self] in
			if let s = self {
				s.updatePrMenu()
				s.prMenu.scrollToTop()
			}
		}

		issuesFilterTimer = PopTimer(timeInterval: 0.2) { [weak self] in
			if let s = self {
				s.updateIssuesMenu()
				s.issuesMenu.scrollToTop()
			}
		}
	}

	func prepareForRefresh() {

		let grayOut = Settings.grayOutWhenRefreshing

		if prMenu.messageView != nil {
			updatePrMenu()
		}
		prMenu.refreshMenuItem.title = " Refreshing..."
		(prMenu.statusItem?.view as? StatusItemView)?.grayOut = grayOut

		if issuesMenu.messageView != nil {
			updateIssuesMenu()
		}
		issuesMenu.refreshMenuItem.title = " Refreshing..."
		(issuesMenu.statusItem?.view as? StatusItemView)?.grayOut = grayOut
	}

	var allowRefresh: Bool = false {
		didSet {
			if allowRefresh {
				prMenu.refreshMenuItem.target = prMenu
				prMenu.refreshMenuItem.action = #selector(MenuWindow.refreshSelected(_:))
				issuesMenu.refreshMenuItem.target = issuesMenu
				issuesMenu.refreshMenuItem.action = #selector(MenuWindow.refreshSelected(_:))
			} else {
				prMenu.refreshMenuItem.action = nil
				prMenu.refreshMenuItem.target = nil
				issuesMenu.refreshMenuItem.action = nil
				issuesMenu.refreshMenuItem.target = nil
			}
		}
	}

	private func updateMenu(type: String, menu: MenuWindow, lengthOffset: CGFloat, totalCount: ()->Int, hasUnread: ()->Bool, reasonForEmpty: (String)->NSAttributedString) {

		func redText() -> [String : AnyObject] {
			return [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
			         NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		}

		func normalText() -> [String : AnyObject] {
			return [ NSFontAttributeName: NSFont.menuBarFontOfSize(10),
			         NSForegroundColorAttributeName: NSColor.controlTextColor() ]
		}

		menu.showStatusItem()

		let countString: String
		let attributes: [String : AnyObject]
		let somethingFailed = ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext)

		if somethingFailed && apiServerId == nil {
			countString = "X"
			attributes = redText()
		} else if somethingFailed, let aid = apiServerId, a = existingObjectWithID(aid) as? ApiServer where !(a.lastSyncSucceeded?.boolValue ?? true) {
			countString = "X"
			attributes = redText()
		} else {

			if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType(type, withFilter: menu.filter.stringValue, sectionIndex: -1, apiServerId: apiServerId)
				countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
			} else {
				countString = String(totalCount())
			}

			if hasUnread() {
				attributes = redText()
			} else {
				attributes = normalText()
			}
		}

		DLog("Updating \(type) menu, \(countString) total items")

		let width = countString.sizeWithAttributes(attributes).width

		let H = NSStatusBar.systemStatusBar().thickness
		let length = H + width + STATUSITEM_PADDING*3
		var updateStatusItem = true
		let shouldGray = Settings.grayOutWhenRefreshing && appIsRefreshing

		if let s = menu.statusItem?.view as? StatusItemView where compareDict(s.textAttributes, to: attributes) && s.statusLabel == countString && s.grayOut == shouldGray {
			updateStatusItem = false
		}

		if updateStatusItem {
			atNextEvent(self) { S in
				DLog("Updating \(type) status item")
				let im = menu
				let siv = StatusItemView(frame: CGRectMake(0, 0, length+lengthOffset, H), label: countString, prefix: type, attributes: attributes)
				siv.labelOffset = lengthOffset
				siv.highlighted = im.visible
				siv.grayOut = shouldGray
				if let aid = S.apiServerId, a = existingObjectWithID(aid) as? ApiServer {
					siv.serverTitle = a.label
				}
				siv.tappedCallback = {
					let m = menu
					if m.visible {
						m.closeMenu()
					} else {
						app.showMenu(m)
					}
				}
				im.statusItem?.view = siv
			}
		}

		menu.reload()

		if menu.table.numberOfRows == 0 {
			menu.messageView = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: reasonForEmpty(menu.filter.stringValue))
		}

		menu.sizeAndShow(false)
	}

	func updateIssuesMenu() {

		if Repo.interestedInIssues(apiServerId) {

			updateMenu("Issue", menu: issuesMenu, lengthOffset: 2, totalCount: { () -> Int in
				return Issue.countOpenInMoc(mainObjectContext)
			}, hasUnread: { [weak self] () -> Bool in
				return Issue.badgeCountInMoc(mainObjectContext, apiServerId: self?.apiServerId) > 0
			}, reasonForEmpty: { filter -> NSAttributedString in
				return Issue.reasonForEmptyWithFilter(filter)
			})

		} else {
			issuesMenu.hideStatusItem()
		}
	}

	func updatePrMenu() {

		if Repo.interestedInPrs(apiServerId) || !Repo.interestedInIssues(apiServerId) {

			updateMenu("PullRequest", menu: prMenu, lengthOffset: 0, totalCount: { () -> Int in
				return PullRequest.countOpenInMoc(mainObjectContext)
			}, hasUnread: { [weak self] () -> Bool in
				return PullRequest.badgeCountInMoc(mainObjectContext, apiServerId: self?.apiServerId) > 0
			}, reasonForEmpty: { filter -> NSAttributedString in
				return PullRequest.reasonForEmptyWithFilter(filter)
			})

		} else {
			prMenu.hideStatusItem()
		}

	}

	private func compareDict(from: [String : AnyObject], to: [String : AnyObject]) -> Bool {
		for (key, value) in from {
			if let v = to[key] {
				if !v.isEqual(value) {
					return false
				}
			} else {
				return false
			}
		}
		return true
	}
}