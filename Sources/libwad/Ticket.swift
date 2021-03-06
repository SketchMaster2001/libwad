//
//  Ticket.swift
//  libwad
//
//  Created by Noah Pistilli on 2021-12-07.
//

import Foundation
import CryptoSwift

/// Ticket defines the binary structure of a given ticket file.
public struct Ticket: Codable {
    public var SignatureType: uint32
    public var Signature: [uint8]
    public var Padding: [uint8]
    public var Issuer: [uint8]
    public var ECDHData: [uint8]
    public var FileVersion: uint8
    public var CACRLVersion: uint8
    public var SignerCRLVersion: uint8
    public var TitleKey: [uint8]
    public var Padding2: uint8
    public var TicketID: uint64
    public var ConsoleID: uint32
    public var TitleID: [uint8]
    public var SystemAccessMask: uint16
    public var TitleVersion: uint16
    public var AccessTitleID: uint32
    public var AccessTitleMask: uint32
    public var LicenseType: uint8
    public var KeyType: KeyTypes
    public var Unknown: [uint8]
    public var TimeLimits: [TimeLimitEntry]
    
    init(data: Data) throws {
        self.SignatureType = readUint32(data, at: pointer)
        pointer += 4
        self.Signature = readBytes(data, length: 256, at: pointer)
        pointer += 256
        self.Padding = readBytes(data, length: 60, at: pointer)
        pointer += 60
        self.Issuer = readBytes(data, length: 64, at: pointer)
        pointer += 64
        self.ECDHData = readBytes(data, length: 60, at: pointer)
        pointer += 60
        self.FileVersion = readByte(data, at: pointer)
        pointer += 1
        self.CACRLVersion = readByte(data, at: pointer)
        pointer += 1
        self.SignerCRLVersion = readByte(data, at: pointer)
        pointer += 1
        self.TitleKey = readBytes(data, length: 16, at: pointer)
        pointer += 16
        self.Padding2 = readByte(data, at: pointer)
        pointer += 1
        self.TicketID = readUint64(data, at: pointer)
        pointer += 8
        self.ConsoleID = readUint32(data, at: pointer)
        pointer += 4
        self.TitleID = readBytes(data, length: 8, at: pointer)
        pointer += 8
        self.SystemAccessMask = readUint16(data, at: pointer)
        pointer += 2
        self.TitleVersion = readUint16(data, at: pointer)
        pointer += 2
        self.AccessTitleID = readUint32(data, at: pointer)
        pointer += 4
        self.AccessTitleMask = readUint32(data, at: pointer)
        pointer += 4
        self.LicenseType = readByte(data, at: pointer)
        pointer += 1
        self.KeyType = KeyTypes(rawValue: readByte(data, at: pointer)) ?? .common
        pointer += 1
        self.Unknown = readBytes(data, length: 114, at: pointer)
        pointer += 114
        
        var array: [TimeLimitEntry] = []
        
        // Read the TimeLimitEntry table
        for _ in 1...8 {
            array.append(
                TimeLimitEntry(
                    code: readUint32(data, at: pointer),
                    limit: readUint32(data, at: pointer+4)
                )
            )
            pointer += 8
        }
        
        self.TimeLimits = array
        
        try self.decryptKey()
    }
}

/// TimeLimitEntry holds a time limit entry for a title.
public struct TimeLimitEntry: Codable {
    public var code: uint32
    public var limit: uint32
}

extension Ticket {
    func selectCommonKey() -> [uint8] {
        switch self.KeyType {
        case .common:
            return CommonKey
        case .korean:
            return KoreanKey
        case .vWii:
            return WiiUvWiiKey
        default:
            return CommonKey
        }
    }
    
    mutating func decryptKey() throws {
        let key = self.selectCommonKey()
        let iv = self.TitleID + [0, 0, 0, 0, 0, 0, 0, 0]
        
        let decrypter = try AES(key: key, blockMode: CBC(iv: iv))
        
        let decryptedKey = try decrypter.decrypt(self.TitleKey)
        
        // Replace encrypted title key with decrypted one
        self.TitleKey = decryptedKey
    }
    
    mutating func encryptKey() throws {
        let key = self.selectCommonKey()
        let iv = self.TitleID + [0, 0, 0, 0, 0, 0, 0, 0]
        
        let encryptor = try AES(key: key, blockMode: CBC(iv: iv))
        
        let encryptedKey = try encryptor.encrypt(self.TitleKey)
        
        // The data for some reason is 32 bytes instead of 16. We must change that
        var goodKey: [uint8] = []
        
        for i in 0...15 {
            goodKey.append(encryptedKey[i])
        }
        
        // Replace encrypted title key with decrypted one
        self.TitleKey = goodKey
    }
}

extension WAD {
    /// Returns the Ticket data in Data
    public func GetTicket() throws -> Data {
        var ticket = self.Ticket
        try ticket.encryptKey()
        
        var dataArray: [uint8] = []
        
        // I do not know of a way to write the contents of a struct directly to Data so here we are...
        dataArray += withUnsafeBytes(of: ticket.SignatureType) { Array($0) }
        dataArray += ticket.Signature
        dataArray += ticket.Padding
        dataArray += ticket.Issuer
        dataArray += ticket.ECDHData
        dataArray.append(ticket.FileVersion)
        dataArray.append(ticket.CACRLVersion)
        dataArray.append(ticket.SignerCRLVersion)
        dataArray += ticket.TitleKey
        dataArray.append(ticket.Padding2)
        dataArray += withUnsafeBytes(of: ticket.TicketID) { Array($0) }
        dataArray += withUnsafeBytes(of: ticket.ConsoleID) { Array($0) }
        dataArray += ticket.TitleID
        dataArray += withUnsafeBytes(of: ticket.SystemAccessMask) { Array($0) }
        dataArray += withUnsafeBytes(of: ticket.TitleVersion) { Array($0) }
        dataArray += withUnsafeBytes(of: ticket.AccessTitleID) { Array($0) }
        dataArray += withUnsafeBytes(of: ticket.AccessTitleMask) { Array($0) }
        dataArray.append(ticket.LicenseType)
        dataArray.append(ticket.KeyType.rawValue)
        dataArray += ticket.Unknown
        
        for limit in ticket.TimeLimits {
            dataArray += withUnsafeBytes(of: limit.code) { Array($0) }
            dataArray += withUnsafeBytes(of: limit.limit) { Array($0) }
        }
        
        return Data(bytes: &dataArray, count: dataArray.count)
    }
    
    /// Loads a Ticket into the WAD struct. Useful for replacing preexisting tickets in WAD's
    public mutating func LoadTicket(data: Data) throws {
        // Store current pointer
        let currentPointer = pointer
        pointer = 0
        
        self.Ticket = try libwad.Ticket(data: data)
        
        // Restore pointer
        pointer = currentPointer
    }
}
