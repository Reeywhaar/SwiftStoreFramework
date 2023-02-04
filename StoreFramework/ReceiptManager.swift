//
//  ReceiptManager.swift
//  StoreFramework
//
//  Created by Mikhail Vyrtsev on 14.01.2023.
//

import Foundation
import StoreKit
import OSLog

public class ReceiptManager: NSObject {
    private let secret: String
    private let receiptURL = Bundle.main.appStoreReceiptURL
    private let sandboxVerifyURL = "https://sandbox.itunes.apple.com/verifyReceipt"
    private var verifyURL = "https://buy.itunes.apple.com/verifyReceipt"
    private var refreshManager: ReceiptRefreshManager?
    private var processor: ReceiptProcessor?
    
    public init(secret: String) {
        self.secret = secret
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: String(describing: ReceiptManager.self))

    public func getAppReceipt() async throws -> AppReceipt {
        do {
            return try await getAppReceipt(verifyURL: verifyURL)
        } catch ReceiptManagerError.sandboxEnvironment {
            return try await getAppReceipt(verifyURL: sandboxVerifyURL)
        }
    }
    
    private func getAppReceipt(verifyURL: String) async throws -> AppReceipt {
        guard let receiptURL = receiptURL else { throw ReceiptManagerError.receiptURLEmpty }
        let refreshManager = ReceiptRefreshManager(receiptURL: receiptURL)
        self.refreshManager = refreshManager
        let receiptData = try await refreshManager.refresh()
        var verifyURL = self.verifyURL
        while true {
            do {
                let processor = ReceiptProcessor(secret: secret, verifyURL: verifyURL, receiptData: receiptData)
                self.processor = processor
                return try await processor.processReceipt()
            } catch ReceiptManagerError.sandboxEnvironment {
                logger.error("Got sandbox status. Switching to sandbox environment")
                verifyURL = self.sandboxVerifyURL
            } catch let error {
                throw error
            }
        }
    }
}

fileprivate class ReceiptRefreshManager: NSObject, SKRequestDelegate {
    var receiptURL: URL
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: String(describing: ReceiptRefreshManager.self))
        
    init(receiptURL: URL) {
        self.receiptURL = receiptURL
    }
    
    private var continuation: CheckedContinuation<Data, Error>?
        
    func refresh() async throws -> Data {
        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Data, Error>) in
            do {
                let receipt = try Data(contentsOf: receiptURL, options: .alwaysMapped)
                continuation.resume(returning: receipt)
            } catch {
                self.continuation = continuation
                let appReceiptRefreshRequest = SKReceiptRefreshRequest(receiptProperties: nil)
                appReceiptRefreshRequest.delegate = self
                appReceiptRefreshRequest.start()
            }
        })
    }
    
    func requestDidFinish(_ request: SKRequest) {
        // a fresh receipt should now be present at the url
        do {
            let receipt = try Data(contentsOf: receiptURL, options: .alwaysMapped)
            logger.error("App receipt refresh request succeed")
            continuation?.resume(returning: receipt)
        } catch {
            logger.error("App receipt refresh request did fail with error: \(error)")
            continuation?.resume(throwing: error)
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        logger.error("App receipt refresh request did fail with error: \(error)")
        continuation?.resume(throwing: error)
    }
}

fileprivate class ReceiptProcessor {
    var secret: String
    var verifyURL: String
    var receiptData: Data
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: String(describing: ReceiptProcessor.self))
    
    init(secret: String, verifyURL: String, receiptData: Data) {
        self.secret = secret
        self.verifyURL = verifyURL
        self.receiptData = receiptData
    }
    
    func processReceipt() async throws -> AppReceipt  {
        let requestDictionary = ["receipt-data": receiptData.base64EncodedString(options: []), "password": secret]

        guard JSONSerialization.isValidJSONObject(requestDictionary) else { throw ReceiptManagerError.requestNotValidJSON }
        let requestData = try JSONSerialization.data(withJSONObject: requestDictionary)
        guard let validationURL = URL(string: verifyURL) else { throw ReceiptManagerError.validationURLCreationFail }
        var request = URLRequest(url: validationURL)
        request.httpMethod = "POST"
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        return try await sendRequest(request: request, requestData: requestData)
    }
    
    private func sendRequest(request: URLRequest, requestData: Data) async throws -> AppReceipt {
        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<AppReceipt, Error>) in
            let session = URLSession(configuration: URLSessionConfiguration.default)
            
            let task = session.uploadTask(with: request, from: requestData) { (data, response, error) in
                do {
                    if let error = error {
                        throw error
                    } else if let data = data {
                        let appReceiptJSON = try! JSONSerialization.jsonObject(with: data)
                        let jsonData = appReceiptJSON as! [String: Any]
                        if let status = jsonData["status"] as? Int, status == 21007 {
                            throw ReceiptManagerError.sandboxEnvironment
                        } else {
                            guard let receiptData = jsonData["receipt"] else { throw ReceiptManagerError.dataEmpty }
                            let data = try JSONSerialization.data(withJSONObject: receiptData)
                            let receipt = try JSONDecoder().decode(AppReceipt.self, from: data)
                            self.logger.info("Received receipt: \(String(data: try! JSONEncoder().encode(receipt), encoding: .utf8)!)")
                            continuation.resume(returning: receipt)
                        }
                    } else {
                        throw ReceiptManagerError.dataEmpty
                    }
                } catch {
                    self.logger.error("Received error on receipt fetch: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        })
    }
}

public struct AppReceiptInAppPurchase: Codable {
    public let product_id: String
}

public struct AppReceipt: Codable {
    public let original_application_version: String
    public let application_version: String
    public let in_app: [AppReceiptInAppPurchase]
}

public enum ReceiptManagerError: LocalizedError {
    case receiptURLEmpty
    case dataEmpty
    case sandboxEnvironment
    case requestNotValidJSON
    case validationURLCreationFail
     
    public var errorDescription: String? {
        switch self {
        case .receiptURLEmpty:
            return "Receipt URL is empty"
        case .dataEmpty:
            return "Data is empty"
        case .sandboxEnvironment:
            return "Request should be made in sandbox environment"
        case .requestNotValidJSON:
            return "Request data is not valid JSON"
        case .validationURLCreationFail:
            return "Can't create verification URL"
        }
        
    }
}

private let RECEIPT_URL_EMPTY = NSLocalizedString("ReceiptManager.RECEIPT_URL_EMPTY", value: "Receipt URL is empty", comment: "")
private let DATA_EMPTY = NSLocalizedString("ReceiptManager.DATA_EMPTY", value: "Data is empty", comment: "")
private let SANDBOX_ENVIRONMENT = NSLocalizedString("ReceiptManager.SANDBOX_ENVIRONMENT", value: "Request should be made in sandbox environment", comment: "")
private let REQUEST_NOT_VALID_JSON = NSLocalizedString("ReceiptManager.REQUEST_NOT_VALID_JSON", value: "Request is not valid JSON", comment: "")
private let VALIDATION_URL_CREATION_FAIL = NSLocalizedString("ReceiptManager.VALIDATION_URL_CREATION_FAIL", value: "Can't create verification URL", comment: "")
