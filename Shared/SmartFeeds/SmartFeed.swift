//
//  SmartFeed.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/19/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import RSCore
import Articles
import ArticlesDatabase
import Account
import Database

final class SmartFeed: PseudoFeed {

	var account: Account? = nil

	var defaultReadFilterType: ReadFilterType {
		return .none
	}

	var sidebarItemID: SidebarItemIdentifier? {
		delegate.sidebarItemID
	}

	var nameForDisplay: String {
		return delegate.nameForDisplay
	}

	var unreadCount = 0 {
		didSet {
			if unreadCount != oldValue {
				postUnreadCountDidChangeNotification()
			}
		}
	}

	var smallIcon: IconImage? {
		return delegate.smallIcon
	}
	
	#if os(macOS)
	var pasteboardWriter: NSPasteboardWriting {
		return SmartFeedPasteboardWriter(smartFeed: self)
	}
	#endif

	private let delegate: SmartFeedDelegate
	private var unreadCounts = [String: Int]()

	init(delegate: SmartFeedDelegate) {
		self.delegate = delegate
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		queueFetchUnreadCounts() // Fetch unread count at startup
	}

	@objc func unreadCountDidChange(_ note: Notification) {
		if note.object is AppDelegate {
			queueFetchUnreadCounts()
		}
	}

	@objc func fetchUnreadCounts() {
		let activeAccounts = AccountManager.shared.activeAccounts
		
		// Remove any accounts that are no longer active or have been deleted
		let activeAccountIDs = activeAccounts.map { $0.accountID }
		unreadCounts.keys.forEach { accountID in
			if !activeAccountIDs.contains(accountID) {
				unreadCounts.removeValue(forKey: accountID)
			}
		}
		
		if activeAccounts.isEmpty {
			updateUnreadCount()
		} else {
			activeAccounts.forEach { self.fetchUnreadCount(for: $0) }
		}
	}
	
}

extension SmartFeed: ArticleFetcher {

	func fetchArticles() throws -> Set<Article> {
		return try delegate.fetchArticles()
	}

	func fetchArticlesAsync(_ completion: @escaping ArticleSetResultBlock) {
		delegate.fetchArticlesAsync(completion)
	}

	func fetchUnreadArticles() throws -> Set<Article> {
		return try delegate.fetchUnreadArticles()
	}

	func fetchUnreadArticlesAsync(_ completion: @escaping ArticleSetResultBlock) {
		delegate.fetchUnreadArticlesAsync(completion)
	}
}

private extension SmartFeed {

	func queueFetchUnreadCounts() {
		CoalescingQueue.standard.add(self, #selector(fetchUnreadCounts))
	}

	func fetchUnreadCount(for account: Account) {
		delegate.fetchUnreadCount(for: account) { singleUnreadCountResult in
			guard let accountUnreadCount = try? singleUnreadCountResult.get() else {
				return
			}
			self.unreadCounts[account.accountID] = accountUnreadCount
			self.updateUnreadCount()
		}
	}

	func updateUnreadCount() {
		unreadCount = AccountManager.shared.activeAccounts.reduce(0) { (result, account) -> Int in
			if let oneUnreadCount = unreadCounts[account.accountID] {
				return result + oneUnreadCount
			}
			return result
		}
	}
}
