
import UIKit
import CoreData

final class RespositoriesViewController: UITableViewController, UISearchResultsUpdating, NSFetchedResultsControllerDelegate {

	enum SortOption {
		case name, prVisibility, issueVisibility, hidingSetting, isFork

		var descriptor: NSSortDescriptor {
			switch self {
			case .name: return NSSortDescriptor(key: "fullName", ascending: true, selector: #selector(NSString.caseInsensitiveCompare))
			case .prVisibility: return NSSortDescriptor(key: "displayPolicyForPrs", ascending: false)
			case .issueVisibility: return NSSortDescriptor(key: "displayPolicyForIssues", ascending: false)
			case .hidingSetting: return NSSortDescriptor(key: "itemHidingPolicy", ascending: false)
			case .isFork: return NSSortDescriptor(key: "fork", ascending: false)
			}
		}
	}

	// Filtering
	private var searchTimer: PopTimer!
	private var currentSortOptions = [SortOption.name]
	private var _fetchedResultsController: NSFetchedResultsController<Repo>?

	@IBOutlet private weak var actionsButton: UIBarButtonItem!
	@IBOutlet weak var setAllPrsItem: UIBarButtonItem!

	@IBAction private func done(_ sender: UIBarButtonItem) {
        presentedViewController?.dismiss(animated: false)
		dismiss(animated: true)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

        definesPresentationContext = true
        
		let searchController = UISearchController(searchResultsController: nil)
		searchController.dimsBackgroundDuringPresentation = false
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchResultsUpdater = self
		searchController.searchBar.tintColor = view.tintColor
		searchController.searchBar.placeholder = "Filter"
		searchController.hidesNavigationBarDuringPresentation = false
		navigationItem.searchController = searchController

		navigationItem.hidesSearchBarWhenScrolling = false
		navigationItem.largeTitleDisplayMode = .automatic

		searchTimer = PopTimer(timeInterval: 0.4) { [weak self] in
			self?.reloadData()
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		actionsButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: DataManager.main)
		if actionsButton.isEnabled && fetchedResultsController.fetchedObjects?.count==0 {
			refreshList()
		} else if let selectedIndex = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: selectedIndex, animated: true)
		}
		super.viewDidAppear(animated)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setToolbarHidden(false, animated: animated)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		navigationController?.setToolbarHidden(true, animated: animated)
	}

	@IBAction private func actionSelected(_ sender: UIBarButtonItem) {
		let r = UIAlertAction(title: "Refresh teams & watchlists", style: .destructive) { _ in
			self.refreshList()
		}
		let w = UIAlertAction(title: "Advanced repo settings…", style: .default) { _ in
			self.performSegue(withIdentifier: "showWatchlistSettings", sender: self)
		}
		let c = UIAlertAction(title: "Custom repos…", style: .default) { _ in
			self.performSegue(withIdentifier: "showCustomRepos", sender: self)
		}
		let cancel = UIAlertAction(title: "Cancel", style: .cancel)

		let v = UIAlertController(title: "Options", message: nil, preferredStyle: .actionSheet)
		v.addAction(r)
		v.addAction(w)
		v.addAction(c)
		v.addAction(cancel)
		present(v, animated: true)
	}

	@IBAction private func setAllPrsSelected(_ sender: UIBarButtonItem) {
		if let ip = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: ip, animated: false)
		}
		performSegue(withIdentifier: "showRepoSelection", sender: self)
	}

	private func setSort(by option: SortOption) {
		if let i = currentSortOptions.firstIndex(of: option) {
			currentSortOptions.remove(at: i)
		}
		currentSortOptions.insert(option, at: 0)
		reloadData()
	}

	@IBAction private func sortSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Sort by...", message: nil, preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Name", style: .default, handler: { _ in
			self.setSort(by: .name)
		}))
		a.addAction(UIAlertAction(title: "PR Visibility", style: .default, handler: { _ in
			self.setSort(by: .prVisibility)
		}))
		a.addAction(UIAlertAction(title: "Issue Visibility", style: .default, handler: { _ in
			self.setSort(by: .issueVisibility)
		}))
		a.addAction(UIAlertAction(title: "Item Hiding", style: .default, handler: { _ in
			self.setSort(by: .hidingSetting)
		}))
		a.addAction(UIAlertAction(title: "Repo Is Fork", style: .default, handler: { _ in
			self.setSort(by: .isFork)
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
	}

	private func refreshList() {
		self.navigationItem.rightBarButtonItem?.isEnabled = false
		let originalName = navigationItem.title
		navigationItem.title = "Loading…"
		actionsButton.isEnabled = false
		tableView.isUserInteractionEnabled = false
		tableView.alpha = 0.5

		NotificationQueue.clear()

		let tempContext = DataManager.buildChildContext()
		API.fetchRepositories(to: tempContext) { [weak self] in
			if ApiServer.shouldReportRefreshFailure(in: tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServers(in: tempContext) {
					if apiServer.goodToGo && !apiServer.lastSyncSucceeded {
						errorServers.append(S(apiServer.label))
					}
				}
				let serverNames = errorServers.joined(separator: ", ")
				showMessage("Error", "Could not refresh repository list from \(serverNames), please ensure that the tokens you are using are valid")
				NotificationQueue.clear()
			} else {
				DataItem.nukeDeletedItems(in: tempContext)
				try! tempContext.save()
				NotificationQueue.commit()
			}
			preferencesDirty = true
			guard let s = self  else { return }
			s.navigationItem.title = originalName
			s.actionsButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: DataManager.main)
			s.tableView.alpha = 1.0
			s.tableView.isUserInteractionEnabled = true
			s.navigationItem.rightBarButtonItem?.isEnabled = true
		}
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return fetchedResultsController.sections?[section].numberOfObjects ?? 0
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! RepoCell
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let vc = segue.destination as? RepoSettingsViewController {
			if let indexPath = tableView.indexPathForSelectedRow {
				vc.repo = fetchedResultsController.object(at: indexPath)
			}
			vc.filter = searchText
		}
	}

	private var searchText: String? {
		if let text = navigationItem.searchController!.searchBar.text?.trim, !text.isEmpty {
			return text
		}
		return nil
	}

	private var fetchedResultsController: NSFetchedResultsController<Repo> {
		if let f = _fetchedResultsController {
			return f
		}

		let fetchRequest = NSFetchRequest<Repo>(entityName: "Repo")
		if let text = searchText {
			fetchRequest.predicate = NSPredicate(format: "fullName contains [cd] %@", text)
			setAllPrsItem.title = "Options for visible repos"
		} else {
			setAllPrsItem.title = "Options for all repos"
		}
		fetchRequest.returnsObjectsAsFaults = false
		fetchRequest.includesSubentities = false
		fetchRequest.fetchBatchSize = 20
		fetchRequest.sortDescriptors = currentSortOptions.map { $0.descriptor }

		let fc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DataManager.main, sectionNameKeyPath: nil, cacheName: nil)
		fc.delegate = self
		_fetchedResultsController = fc

		try! fc.performFetch()

		if (fc.fetchedObjects?.count ?? 0) == 0 {
			navigationController?.setToolbarHidden(true, animated: true)
		} else {
			navigationController?.setToolbarHidden(false, animated: true)
		}

		return fc
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		tableView.reloadData()
	}

	private func configureCell(_ cell: RepoCell, atIndexPath: IndexPath) {
		let repo = fetchedResultsController.object(at: atIndexPath)

		let titleColor: UIColor = repo.shouldSync ? labelColour : tertiaryLabelColour
		let titleAttributes = [ NSAttributedString.Key.foregroundColor: titleColor ]

		let title = NSMutableAttributedString(attributedString: NSAttributedString(string: S(repo.fullName), attributes: titleAttributes))
		title.append(NSAttributedString(string: "\n", attributes: titleAttributes))
		let groupTitle = groupTitleForRepo(repo: repo)
		title.append(groupTitle)

		cell.titleLabel.attributedText = title
		let prTitle = prTitleForRepo(repo: repo)
		let issuesTitle = issueTitleForRepo(repo: repo)
		let hidingTitle = hidingTitleForRepo(repo: repo)

		cell.prLabel.attributedText = prTitle
		cell.issuesLabel.attributedText = issuesTitle
		cell.hidingLabel.attributedText = hidingTitle
		cell.forkLabel.text = repo.fork ? "Fork" : nil
		cell.accessibilityLabel = "\(title), \(prTitle.string), \(issuesTitle.string), \(hidingTitle.string), \(groupTitle.string)"
	}

	private var sizer: RepoCell?
	private var heightCache = [IndexPath : CGFloat]()
	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if sizer == nil {
			sizer = tableView.dequeueReusableCell(withIdentifier: "Cell") as? RepoCell
		} else if let h = heightCache[indexPath] {
			//DLog("using cached height for %@ - %@", indexPath.section, indexPath.row)
			return h
		}
		configureCell(sizer!, atIndexPath: indexPath)
		let h = sizer!.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: 0),
		                                       withHorizontalFittingPriority: .required,
		                                       verticalFittingPriority: .fittingSizeLevel).height
		heightCache[indexPath] = h
		return h
	}

	private func titleForRepo(repo: Repo) -> NSAttributedString {

		let fullName = S(repo.fullName)
		let text = repo.inaccessible ? "\(fullName) (inaccessible)" : fullName
		let color: UIColor = repo.shouldSync ? labelColour : tertiaryLabelColour
		return NSAttributedString(string: text, attributes: [ NSAttributedString.Key.foregroundColor: color ])
	}

	private func prTitleForRepo(repo: Repo) -> NSAttributedString {

		let policy = RepoDisplayPolicy(repo.displayPolicyForPrs) ?? .hide
		return NSAttributedString(string: "PR Sections: \(policy.name)", attributes: attributes(for: policy))
	}

	private func issueTitleForRepo(repo: Repo) -> NSAttributedString {

		let policy = RepoDisplayPolicy(repo.displayPolicyForIssues) ?? .hide
		return NSAttributedString(string: "Issue Sections: \(policy.name)", attributes: attributes(for: policy))
	}

	private func groupTitleForRepo(repo: Repo) -> NSAttributedString {
		if let l = repo.groupLabel {
			return NSAttributedString(string: "Group: \(l)", attributes: [
				NSAttributedString.Key.foregroundColor : secondaryLabelColour,
				NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
				])
		} else {
			return NSAttributedString(string: "Ungrouped", attributes: [
				NSAttributedString.Key.foregroundColor : tertiaryLabelColour,
				NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
				])
		}
	}

	private func hidingTitleForRepo(repo: Repo) -> NSAttributedString {

		let policy = RepoHidingPolicy(repo.itemHidingPolicy) ?? .noHiding
		return NSAttributedString(string: policy.name, attributes: attributes(for: policy))
	}

	private func attributes(for policy: RepoDisplayPolicy) -> [NSAttributedString.Key : Any] {
		return [
			NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize-1.0),
			NSAttributedString.Key.foregroundColor: policy.color
		]
	}

	private func attributes(for policy: RepoHidingPolicy) -> [NSAttributedString.Key : Any] {
		return [
			NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize-1.0),
			NSAttributedString.Key.foregroundColor: policy.color
		]
	}

	///////////////////////////// filtering

	private func reloadData() {

		heightCache.removeAll()

		let currentIndexes = IndexSet(integersIn: Range(uncheckedBounds: (0, fetchedResultsController.sections?.count ?? 0)))

		_fetchedResultsController = nil

		let dataIndexes = IndexSet(integersIn: Range(uncheckedBounds: (0, fetchedResultsController.sections?.count ?? 0)))

		let removedIndexes = currentIndexes.filter { !dataIndexes.contains($0) }
		let addedIndexes = dataIndexes.filter { !currentIndexes.contains($0) }
		let untouchedIndexes = dataIndexes.filter { !(removedIndexes.contains($0) || addedIndexes.contains($0)) }

		tableView.beginUpdates()
		if removedIndexes.count > 0 {
			tableView.deleteSections(IndexSet(removedIndexes), with: .fade)
		}
		if untouchedIndexes.count > 0 {
			tableView.reloadSections(IndexSet(untouchedIndexes), with:.fade)
		}
		if addedIndexes.count > 0 {
			tableView.insertSections(IndexSet(addedIndexes), with: .fade)
		}
		tableView.endUpdates()


	}

	override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		let searchBar = navigationItem.searchController!.searchBar
		if searchBar.isFirstResponder {
			searchBar.resignFirstResponder()
		}
	}

	func updateSearchResults(for searchController: UISearchController) {
		searchTimer.push()
	}
}
