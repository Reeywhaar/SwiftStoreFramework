//
//  IAPManager.swift
//  StoreFramework
//
//  Created by Mikhail Vyrtsev on 26.07.2021.
//

import Foundation
import StoreKit
import os
import Combine

public typealias IAPProductIdentifier = String

public class IAPManager: NSObject, ObservableObject {
    @Published public private(set) var purchaseState: [IAPProductIdentifier: IAPPurchaseState] = [:]
    
    private var productsRequest: SKProductsRequest?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: String(describing: IAPManager.self))
    private var restoreManager: IAPRestoreManager?
    private var purchaseManagers: Set<IAPPurchaseManager> = Set()
    
    public var purchaseInProgress: Bool {
        return purchaseState.first { (key, value) in
            if case .loading = value { return true }
            return false
        } != nil
    }
        
    public var isAuthorizedForPayments: Bool {
        return SKPaymentQueue.canMakePayments()
    }
    
    public func restorePurchases() async throws -> [IAPProductIdentifier] {
        do {
            if !isAuthorizedForPayments {
                throw IAPManagerError.notAuthorizedForPayment
            }
            self.restoreManager = IAPRestoreManager()
            defer { self.restoreManager = nil }
            let transactions = try await self.restoreManager!.restore()
            for transaction in transactions {
                purchaseState[transaction.payment.productIdentifier] = IAPPurchaseState(fromTransaction: transaction)
            }
            return transactions.compactMap {
                $0.payment.productIdentifier
            }
        } catch {
            throw error
        }
    }
    
    public func purchaseProduct(identifier: IAPProductIdentifier) async throws {
        logger.info("Purchasing \(identifier)")
        if let productIdentifierState = purchaseState[identifier] {
            if productIdentifierState.isPurchased {
                logger.info("\(identifier) already purchased")
                updateIdentifier(identifier, .purchased)
                return
            }
            if case .loading = productIdentifierState {
                logger.info("\(identifier) is already in progress")
                return
            }
        }
        
        do {
            let purchaseManager = IAPPurchaseManager()
            self.purchaseManagers.insert(purchaseManager)
            defer {
                self.purchaseManagers.remove(purchaseManager)
            }
            updateIdentifier(identifier, .loading)
            try await purchaseManager.purchase(identifier)
            updateIdentifier(identifier, .purchased)
        } catch {
            updateIdentifier(identifier, .error(error))
            throw error
        }
    }
    
    public func purchaseInProgress(for identifier: IAPProductIdentifier) -> Bool {
        if case .loading = purchaseState[identifier] { return true }
        return false
    }
    
    // MARK: - privates
        
    private func updateIdentifier(_ key: IAPProductIdentifier, _ state: IAPPurchaseState) {
        DispatchQueue.main.async {
            self.purchaseState[key] = state
        }
    }
}

public enum IAPManagerError: LocalizedError {
    case purchaseFailed
    case notAuthorizedForPayment
    case alreadyInProgress
    
    var errorDescription: String {
        switch self {
        case .purchaseFailed:
            return PURCHASE_FAILED
        case .notAuthorizedForPayment:
            return NOT_AUTHORIZED_FOR_PAYMENT
        case .alreadyInProgress:
            return ALREADY_IN_PROGRESS
        }
    }
}

private let PURCHASE_FAILED = NSLocalizedString("IAPManager.PURCHASE_FAILED", value: "Purchase failed", comment: "")
private let NOT_AUTHORIZED_FOR_PAYMENT = NSLocalizedString("IAPManager.NOT_AUTHORIZED_FOR_PAYMENT", value: "Not authorized for payment", comment: "")
private let ALREADY_IN_PROGRESS = NSLocalizedString("IAPManager.ALREADY_IN_PROGRESS", value: "Action already in progress", comment: "")
