//
//  EdmTools.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 21.10.21.
//

import Foundation

struct EdmFileParser {
    var data : Data = Data()
    var edmFileData : EdmFileData = EdmFileData()
    var nextread  = 0
    var eor = false // signals end of record
    var headerChecksum : UInt8 = 0
    var nextFlightIndex : Int?
    var complete = false
    var invalid = false
    
    var available : Int {
        return data.count - nextread
    }
    
    var values : [String] = []
    var item : String?

    mutating func setData (_ data1: Data){
        data = data1
    }
    
    subscript(index: Data.Index) -> Character {
        return Character(Unicode.Scalar(data[index]))
    }
    
    mutating func readChar() -> Character {
        let c = self[nextread]
        
        //print ("read char: " + String(c) + " (" + String(Int(c.asciiValue ?? 0)) + ")")
        headerChecksum ^= UInt8(c.asciiValue ?? 0)
        nextread += 1
        return c
    }
    
    mutating func readUShort() -> UInt16 {
        let us = UInt16(data[nextread]) << 8 + UInt16(data[nextread+1])
        nextread += 2
        return us
    }
    
    mutating func nextHeaderItem () -> String? {
        var c : Character
        var newItem : String?
        var skip = false
        
        while available > 0 {
            c = readChar()

            if (c == ","){
                return newItem
            }
            if (c == "*"){
                // checksum without the "trailing" *
                headerChecksum ^= UInt8(c.asciiValue ?? 0)
                eor = true
                print("new Item: " + (newItem ?? "nil"))
                return newItem
            }

            if (c.isLetter || c.isNumber){
                if skip {
                    continue
                }
                
                //print("found letter: " + String(c))
                if (newItem == nil){
                    newItem = String(c)
                } else {
                    newItem!.append(String(c))
                }
            } else if (c.isASCII || c.isWhitespace){
                if newItem != nil {
                    skip = true
                }
            }
        }

        return String()
    }
    
    mutating func parseHeaderLine () -> EdmHeaderLine {
        var hl : EdmHeaderLine = EdmHeaderLine()
        var linetypechar : Character = Character("I")
        eor = false
        headerChecksum = 0
        
        if available > 1 {
            if self[0] != "$" {
                return hl
            }
            nextread += 1
            linetypechar = readChar()
        }
        
        while available > 0 && eor == false {
            item = nextHeaderItem()
            if item != nil {
                hl.contents.append(item!)
            }
        }
        
        if available > 2 {
            // read checksum
            var s : String = String(self[nextread])
            s.append(self[nextread + 1])
            let cs = UInt8(s, radix: 16)
        
            if cs != headerChecksum {
                print ("checksum error: " + String(cs ?? 0) + " != " + String(headerChecksum) + " (" + s + ")")
            }
            nextread += 2
            
            // read \n\r
            if self[nextread] != "\r" || self[nextread + 1] != "\n" {
                print("invalid token at EOL " + String(self[nextread]))
                nextread += 2
                hl.lineType = .lineTypeInvalid
                return hl
            }
            nextread += 2
        }
                
        switch linetypechar {
            case "U":
                hl.lineType = .lineTypeRegistration
            case "A":
                hl.lineType = .lineTypeAlert
            case "F":
                hl.lineType = .lineTypeFuelFlow
            case "T":
                hl.lineType = .lineTypeTimestamp
            case "C":
                hl.lineType = .lineTypeConfig
            case "D":
                hl.lineType = .lineTypeFlight
            case "L":
                hl.lineType = .lineTypeLastLine
            default:
                hl.lineType = .lineTypeInvalid
        }
        
        if hl.lineType == .lineTypeInvalid {
            print ("invalid line type: %c\n", linetypechar)
        }
        print ("return new line, type: " + String(linetypechar))
        return hl
    }
    
    mutating func parse () {
        // var fileheader : EdmFileHeader?
        if edmFileData.edmFileHeader == nil {
            
            guard available > 2000 else {
                return
            }
            
            guard let fileheader = parseFileHeaders() else {
                return
            }
            
            edmFileData.edmFileHeader = fileheader
        }
        
        while available > edmFileData.edmFileHeader!.flightInfos[nextFlightIndex!].sizeBytes {
            _ = parseFlightHeaderAndSkip()
        }
    }
    
    mutating func parseFlightHeaderAndSkip () -> EdmFlightHeader? {
        
        guard let flightheader = parseFlightHeader() else {
            return nil
        }
        
        guard nextFlightIndex! < edmFileData.edmFileHeader!.flightInfos.count else {
            print ("invalid flight indes" + String(nextFlightIndex!))
            return nil
        }
        
        let size = edmFileData.edmFileHeader!.flightInfos[nextFlightIndex!].sizeBytes - 15
        nextread += size
        nextFlightIndex! += 1
        if nextFlightIndex == edmFileData.edmFileHeader!.flightInfos.count {
            complete = true
        }
        
        return flightheader
    }
    
    mutating func parseFlightHeader () -> EdmFlightHeader? {
        
        guard available > 15 else {
            return nil
        }
        
        var a : [UInt16]  = []
        
        for _ in 0...6 {
            a.append(readUShort())
        }
        
        let cs = Int8(self[nextread].asciiValue ?? 0)
        nextread += 1
        
        let fh = EdmFlightHeader(values: a, checksum: cs)
        var efd = EdmFlightDatum()
        efd.flightHeader = fh
        edmFileData.edmFlightData.append(efd)
        
        return fh
    }
    
    mutating func parseFileHeaders () -> EdmFileHeader? {
        var edmFileHeader =  EdmFileHeader()
        var hl = EdmHeaderLine()

        while hl.lineType != .lineTypeLastLine {
            hl = parseHeaderLine()
            switch hl.lineType {
                case .lineTypeRegistration:
                    edmFileHeader.registration = edmFileHeader.initRegistration(hl.contents) ?? ""
                case .lineTypeAlert:
                    edmFileHeader.alarms = EdmAlarmLimits(hl.contents)
                case .lineTypeFuelFlow:
                    edmFileHeader.ff = EdmFuelFlow(hl.contents)
                case .lineTypeTimestamp:
                    edmFileHeader.date = edmFileHeader.initDate(hl.contents)
                case .lineTypeConfig:
                    edmFileHeader.config = EdmConfig(hl.contents)
                case .lineTypeFlight:
                    edmFileHeader.flightInfos.append(EdmFlightInfo(hl.contents))
                case .lineTypeLastLine:
                    break
            case .lineTypeInvalid:
                    return nil
            }
        }
        
        edmFileHeader.headerLen = nextread
        edmFileHeader.totalLen = edmFileHeader.headerLen
        
        for flight in edmFileHeader.flightInfos {
            edmFileHeader.totalLen += flight.sizeBytes
        }

        nextFlightIndex = 0
        return edmFileHeader
    }
}


struct EdmHeaderLine {
    
    static let MAX_LEN = 256
    enum EdmLineType {
        case lineTypeInvalid
        case lineTypeRegistration
        case lineTypeAlert
        case lineTypeFuelFlow
        case lineTypeTimestamp
        case lineTypeConfig
        case lineTypeFlight
        case lineTypeLastLine
    }
    
    var lineType : EdmLineType = .lineTypeInvalid
    var contents : [String] = []
    var registration : String = ""
    var checkSum : Int
    
    init() {
        lineType = .lineTypeInvalid
        contents = []
        checkSum = 0
    }
    
}

extension Date
{
    func toString( dateFormat format  : String ) -> String
    {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        return dateFormatter.string(from: self)
    }

}

