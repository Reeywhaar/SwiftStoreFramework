//
//  IAPPurchaseManager.swift
//  StoreFramework
//
//  Created by Mikhail Vyrtsev on 26.01.2023.
//

import Foundation
import StoreKit
import OSLog

public class IAPPurchaseManager: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: String(describing: IAPPurchaseManager.self))
    private var request: SKProductsRequest?
    private var productIdentifier: IAPProductIdentifier?
    private var continuation: CheckedContinuation<Void, Error>?
    
    deinit {
        logger.info("Stop observing transactions")
        SKPaymentQueue.default().remove(self)
    }
    
    public func purchase(_ productIdentifier: IAPProductIdentifier) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            self.productIdentifier = productIdentifier
            let request = SKProductsRequest(productIdentifiers: [productIdentifier])
            request.delegate = self
            request.start()
            self.request = request
        }
    }
    
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        logger.info("Loaded list of products")
        for product in response.products {
            if product.productIdentifier == self.productIdentifier! {
                buyProduct(product)
            }
        }
        for invalid in response.invalidProductIdentifiers {
            if invalid == self.productIdentifier! {
                continuation?.resume(throwing: IAPPurchaseManagerError.invalidIdentifier)
            }
        }
    }
        
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        if request == self.request {
            continuation?.resume(throwing: error)
        }
    }
    
    private func buyProduct(_ product: SKProduct) {
        SKPaymentQueue.default().add(self)
        logger.info("Buying \(product.productIdentifier)...")
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            if transaction.payment.productIdentifier == self.productIdentifier {
                switch transaction.transactionState {
                case .restored, .purchased:
                    continuation?.resume()
                    return
                case .failed:
                    continuation?.resume(throwing: transaction.error!)
                    return
                default:
                    return
                }
            }
        }
    }
}


public enum IAPPurchaseManagerError: LocalizedError {
    case invalidIdentifier
    
    var errorDescription: String {
        switch self {
        case .invalidIdentifier:
            return INVALID_IDENTIFIER
        }
    }
}

private let INVALID_IDENTIFIER = NSLocalizedString("IAPPurchaseManager.INVALID_IDENTIFIER", value: "Invalid identifier", comment: "")
