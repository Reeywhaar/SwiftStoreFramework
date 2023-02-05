//
//  PurchaseState.swift
//  StoreFramework
//
//  Created by Mikhail Vyrtsev on 18.01.2023.
//

import Foundation
import StoreKit
import Combine

public enum IAPPurchaseState {
    case loading
    case purchased
    case error(Error)
    
    public var isProcessed: Bool {
        switch self {
        case .loading, .purchased: return true
        default: return false
        }
    }
    
    public var isPurchased: Bool {
        switch self {
        case .purchased: return true
        default: return false
        }
    }
    
    init?(fromTransaction transaction: SKPaymentTransaction) {
        switch transaction.transactionState {
        case .restored, .purchased:
            self = .purchased
            return
        case .failed:
            self = .error(transaction.error!)
            return
        case .purchasing, .deferred:
            self = .loading
            return
        @unknown default:
            return nil
        }
    }
}
