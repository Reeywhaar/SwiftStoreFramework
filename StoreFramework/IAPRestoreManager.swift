//
//  IAPRestoreManager.swift
//  StoreFramework
//
//  Created by Mikhail Vyrtsev on 26.01.2023.
//

import Foundation
import StoreKit
import OSLog
import Combine

public class IAPRestoreManager: NSObject, SKPaymentTransactionObserver {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: String(describing: IAPRestoreManager.self))
    private var continuation: CheckedContinuation<[SKPaymentTransaction], Error>?
    
    deinit {
        logger.info("Stop observing transactions")
        SKPaymentQueue.default().remove(self)
    }
    
    public func restore() async throws -> [SKPaymentTransaction] {
        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<[SKPaymentTransaction], Error>) in
            logger.info("Restoring transactions")
            self.continuation = continuation
            SKPaymentQueue.default().add(self)
            SKPaymentQueue.default().restoreCompletedTransactions()
        })
    }
    
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        logger.info("Restored transactions")
        continuation?.resume(returning: queue.transactions)
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        logger.error("Transactions restore failed \(error)")
        continuation?.resume(throwing: error)
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {}
}
