
final class AdvancedReposWindow : NSWindow, NSWindowDelegate {

	@IBOutlet private weak var refreshReposLabel: NSTextField!
	@IBOutlet private weak var refreshButton: NSButton!
	@IBOutlet private weak var activityDisplay: NSProgressIndicator!
	@IBOutlet private weak var repoCheckStepper: NSStepper!

	@IBOutlet private weak var autoAddRepos: NSButton!
	@IBOutlet private weak var autoRemoveRepos: NSButton!
	@IBOutlet private weak var hideArchivedRepos: NSButton!

    @IBOutlet private weak var syncAuthoredPrs: NSButton!
    @IBOutlet private weak var syncAuthoredIssues: NSButton!

	weak var prefs: PreferencesWindow?

	override func awakeFromNib() {
		super.awakeFromNib()
		delegate = self

		refreshButton.toolTip = "Reload all watchlists now. Normally Trailer does this by itself every few hours. You can control how often from the 'Display' tab."
		refreshReposLabel.toolTip = Settings.newRepoCheckPeriodHelp
		repoCheckStepper.toolTip = Settings.newRepoCheckPeriodHelp
		repoCheckStepper.floatValue = Settings.newRepoCheckPeriod
        syncAuthoredPrs.toolTip = Settings.queryAuthoredPRsHelp
        syncAuthoredIssues.toolTip = Settings.queryAuthoredIssuesHelp

        autoAddRepos.integerValue = Settings.automaticallyAddNewReposFromWatchlist ? 1 : 0
		autoRemoveRepos.integerValue = Settings.automaticallyRemoveDeletedReposFromWatchlist ? 1 : 0
		hideArchivedRepos.integerValue = Settings.hideArchivedRepos ? 1 : 0
        syncAuthoredPrs.integerValue = Settings.queryAuthoredPRs ? 1 : 0
        syncAuthoredIssues.integerValue = Settings.queryAuthoredIssues ? 1 : 0

		newRepoCheckChanged(nil)

		updateActivity()

		let allServers = ApiServer.allApiServers(in: DataManager.main)
		if allServers.count > 1 {
			let m = NSMenuItem()
			m.title = "Select a server…"
			serverPicker.menu?.addItem(m)
		}
		for s in allServers {
			let m = NSMenuItem()
			m.representedObject = s
			m.title = s.label ?? "(no label)"
			serverPicker.menu?.addItem(m)
		}
	}

	func windowWillClose(_ notification: Notification) {
		prefs?.closedAdvancedWindow()
	}

	// chain this to updateActivity from the main repferences window
	func updateActivity() {
        if API.isRefreshing {
			refreshButton.isEnabled = false
			activityDisplay.startAnimation(nil)
		} else {
			refreshButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: DataManager.main)
			activityDisplay.stopAnimation(nil)
			updateRemovableRepos()
		}
		addButton.isEnabled = !API.isRefreshing
		removeButton.isEnabled = !API.isRefreshing
	}

	private func updateRemovableRepos() {
		removeRepoList.removeAllItems()
		let manuallyAddedRepos = Repo.allItems(of: Repo.self, in: DataManager.main).filter { $0.manuallyAdded }
		if manuallyAddedRepos.isEmpty {
			let m = NSMenuItem()
			m.title = "You have not added any custom repositories"
			removeRepoList.menu?.addItem(m)
			removeRepoList.isEnabled = false
		} else if manuallyAddedRepos.count > 1 {
			let m = NSMenuItem()
			m.title = "Select a custom repository to remove…"
			removeRepoList.menu?.addItem(m)
			removeRepoList.isEnabled = true
		}
		for r in manuallyAddedRepos {
			let m = NSMenuItem()
			m.representedObject = r
			m.title = r.fullName ?? "(no label)"
			removeRepoList.menu?.addItem(m)
			removeRepoList.isEnabled = true
		}
	}

	@IBAction private func newRepoCheckChanged(_ sender: NSStepper?) {
		Settings.newRepoCheckPeriod = repoCheckStepper.floatValue
		refreshReposLabel.stringValue = "Re-scan every \(repoCheckStepper.integerValue) hours"
	}

	@IBAction private func refreshReposSelected(_ sender: NSButton?) {
		prefs?.refreshRepos()
	}

	@IBAction private func autoHideArchivedReposSelected(_ sender: NSButton) {
		Settings.hideArchivedRepos = sender.integerValue == 1
		if Settings.hideArchivedRepos && Repo.hideArchivedRepos(in: DataManager.main) {
			prefs?.reloadRepositories()
			updateRemovableRepos()
			app.updateAllMenus()
			DataManager.saveDB()
		}
	}
    
    @IBAction private func queryAuthoredPRsSelected(_ sender: NSButton) {
        Settings.queryAuthoredPRs = (sender.integerValue == 1)
        lastRepoCheck = .distantPast
        preferencesDirty = true
    }

    @IBAction private func queryAuthoredIssuesSelected(_ sender: NSButton) {
        Settings.queryAuthoredIssues = (sender.integerValue == 1)
        lastRepoCheck = .distantPast
        preferencesDirty = true
    }

	@IBAction private func automaticallyAddNewReposSelected(_ sender: NSButton) {
		let set = sender.integerValue == 1
		Settings.automaticallyAddNewReposFromWatchlist = set
		if set {
			prepareReposForSync()
		}
	}

	private func prepareReposForSync() {
		lastRepoCheck = .distantPast
		for a in ApiServer.allApiServers(in: DataManager.main) {
			for r in a.repos {
				r.resetSyncState()
			}
		}
		DataManager.saveDB()
	}

	@IBAction private func automaticallyRemoveReposSelected(_ sender: NSButton) {
		let set = sender.integerValue == 1
		Settings.automaticallyRemoveDeletedReposFromWatchlist = set
		if set {
			prepareReposForSync()
		}
		DataManager.saveDB()
	}

	@IBOutlet private weak var serverPicker: NSPopUpButton!
	@IBOutlet private weak var newRepoOwner: NSTextField!
	@IBOutlet private weak var newRepoName: NSTextField!
	@IBOutlet private weak var newRepoSpinner: NSProgressIndicator!
	@IBOutlet private weak var addButton: NSButton!

	@IBAction private func addSelected(_ sender: NSButton) {
		let name = newRepoName.stringValue.trim
		let owner = newRepoOwner.stringValue.trim
		guard
			!name.isEmpty,
			!owner.isEmpty,
			let server = serverPicker.selectedItem?.representedObject as? ApiServer
			else {
				let alert = NSAlert()
				alert.messageText = "Missing Information"
				alert.informativeText = "Please select a server, provide an owner/org name, and the name of the repo (or a star for all repos). Usually this info is part of the repository's URL, like https://github.com/owner_or_org/repo_name"
				alert.addButton(withTitle: "OK")
				alert.beginSheetModal(for: self, completionHandler: nil)
				return
		}

		newRepoSpinner.startAnimation(nil)
		addButton.isEnabled = false

		if name == "*" {
			API.fetchAllRepos(owner: owner, from: server) { error in
				self.newRepoSpinner.stopAnimation(nil)
				self.addButton.isEnabled = true
				preferencesDirty = true

				let alert = NSAlert()
				if let e = error {
					alert.messageText = "Fetching Repository Information Failed"
					alert.informativeText = e.localizedDescription
				} else {
					let addedCount = Repo.newItems(of: Repo.self, in: DataManager.main).count
					alert.messageText = "\(addedCount) repositories added for '\(owner)'"
					if Settings.displayPolicyForNewPrs == Int(RepoDisplayPolicy.hide.rawValue) && Settings.displayPolicyForNewIssues == Int(RepoDisplayPolicy.hide.rawValue) {
						alert.informativeText = "WARNING: While \(addedCount) repositories have been added successfully to your list, your default settings specify that they should be hidden. You probably want to change their visibility from the repositories list."
					} else {
						alert.informativeText = "The new repositories have been added to your local list. Trailer will refresh after you close preferences to fetch any items from them."
					}
					DataManager.saveDB()
					self.prefs?.reloadRepositories()
					self.updateRemovableRepos()
					app.updateAllMenus()
				}
				alert.addButton(withTitle: "OK")
				alert.beginSheetModal(for: self, completionHandler: nil)

			}
		} else {
			API.fetchRepo(named: name, owner: owner, from: server) { error in

				self.newRepoSpinner.stopAnimation(nil)
				self.addButton.isEnabled = true
				preferencesDirty = true

				let alert = NSAlert()
				if let e = error {
					alert.messageText = "Fetching Repository Information Failed"
					alert.informativeText = e.localizedDescription
				} else {
					alert.messageText = "Repository added"
					if Settings.displayPolicyForNewPrs == Int(RepoDisplayPolicy.hide.rawValue) && Settings.displayPolicyForNewIssues == Int(RepoDisplayPolicy.hide.rawValue) {
						alert.informativeText = "WARNING: While the repository has been added successfully to your list, your default settings specify that it should be hidden. You probably want to change its visibility from the repositories list."
					} else {
						alert.informativeText = "The new repository has been added to your local list. Trailer will refresh after you close preferences to fetch any items from it."
					}
					DataManager.saveDB()
					self.prefs?.reloadRepositories()
					self.updateRemovableRepos()
					app.updateAllMenus()
				}
				alert.addButton(withTitle: "OK")
				alert.beginSheetModal(for: self, completionHandler: nil)
			}
		}
	}

	@IBOutlet private weak var removeRepoList: NSPopUpButtonCell!
	@IBOutlet private weak var removeButton: NSButton!
	@IBAction private func removeSelected(_ sender: NSButton) {
		guard let repo = removeRepoList.selectedItem?.representedObject as? Repo else { return }
		DataManager.main.delete(repo)
		DataManager.saveDB()
		prefs?.reloadRepositories()
		updateRemovableRepos()
		app.updateAllMenus()
	}
}
