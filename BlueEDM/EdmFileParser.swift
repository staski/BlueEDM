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

    var flightRecords : [EdmFlightDataRecord] = []
    
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
    
    mutating func readByte() -> UInt8 {
        let b = data[nextread]
        nextread += 1
        return b
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
                trc(level: .info, string: "new Item: " + (newItem ?? "nil"))
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
    
    mutating func parseFlightDataRecord(rec original: EdmFlightDataRecord) ->EdmFlightDataRecord {
        var rdr = EdmRawDataRecord()
        var rec = original
        
        // read the decode flagw
        guard let df = parseFlightDecodeFlags() else {
            return rec
        }
        rdr.decodeFlags = df
        trc(level: .info, string: "decode flags:" + String(df.rawValue, radix: 2))
        
        rdr.repeatCount = Int8(readByte())
        trc(level: .info, string: "repeat count: \(rdr.repeatCount)")
        
        // read the compressed value flags
        // TODO assert rdr.valueFlags.numberOfBytes <= rdr.decodeFlags.numberofBits
        var value64 : Int64 = 0
        for i in 0..<rdr.valueFlags.numberOfBytes {
            if rdr.decodeFlags!.hasBit(i: i) {
                var tmp = Int64(readByte())
                trc(level: .info, string: "f_value \(i): \(tmp) " + String(tmp, radix: 2) + ", " + String(tmp, radix: 16))
                tmp <<= i*8
                value64 += tmp
            }
        }
        rdr.valueFlags = EdmValueFlags(rawValue: value64)
        trc(level: .info, string: "valueFlags: \(value64), Binary: " + String(value64, radix: 16))
               
        // read the compressed scale flags
        var value16 : Int16 = 0
        for i in 0..<rdr.scaleFlags.numberOfBytes {
            if rdr.decodeFlags!.hasBit(i: i + rdr.valueFlags.numberOfBytes) {
                var tmp = Int16(readByte())
                trc(level: .info, string: "f_scale \(i): \(tmp) " + String(tmp, radix: 2) + ", " + String(tmp, radix: 16))
                tmp <<= i*8
                value16 += tmp
            }
        }
        rdr.scaleFlags = EdmScaleFlags(rawValue: value16)

        // read the compressed signflags
        // TODO assert rdr.signFlags.numberOfBytes <= rdr.decodeFlags.numberofBits
        value64 = 0
        for i in 0..<rdr.signFlags.numberOfBytes {
            if rdr.decodeFlags!.hasBit(i: i) {
                var tmp = Int64(readByte())
                trc(level: .info, string: "f_sign \(i): \(tmp) " + String(tmp, radix: 2) + ", " + String(tmp, radix: 16))
                tmp <<= i*8
                value64 += tmp
            }
        }
        rdr.signFlags = EdmSignFlags(rawValue: value64)
        
        // read compressed values and compute naflags
        for i in 0..<rdr.valueFlags.numberOfBits {
            if rdr.valueFlags.hasBit(i: i){
                let val8 = readByte();
                if val8 != 0 {
                    rec.naflags.clearBit(i: i)
                } else {
                    rec.naflags.setBit(i: i)
                }
                rdr.values[i] += (rdr.signFlags.hasBit(i: i) ? -1 : 1) * Int16(UInt16(val8))
                
                trc(level: .info, string: "value \(i) val8 \(val8), values: \(rdr.values[i])")
            }
        }
        
        // cmpute scaled egt values
        for i in 0..<rdr.scaleFlags.numberOfBytes {
            for j in 0..<8 {
                if rdr.scaleFlags.hasBit(i: i*8+j) {
                    let idx = j+i*24 //24 is the index of the second engine's egt values
                    var tmp = Int16(readByte())
                    tmp <<= 8
                    //let val16 : Int16 = Int16(readByte()) << 8;
                    if tmp != 0 {
                        rec.naflags.clearBit(i: idx)
                    } else {
                        rec.naflags.setBit(i: idx)
                    }
                    rdr.values[idx] += (rdr.signFlags.hasBit(i: idx) ? -1 : 1) * tmp
                    trc(level: .info, string: "\(idx): \(tmp) (" + String(tmp, radix: 2) + "), \(rdr.values[idx]) (" + String(rdr.values[idx], radix: 16) + ")")
                }
            }
        }
        
        // special case for the rpm value (byte 41 and hi value only present for single engine)
        if edmFileData.edmFileHeader != nil{
            let numOfEngines = edmFileData.edmFileHeader?.config.numOfEngines()
            if numOfEngines == 1 {
                if rdr.signFlags.hasBit(i: 41) {
                    rdr.values[42] -= rdr.values[42]
                }
                if rdr.values[42] != 0 {
                    rec.naflags.clearBit(i: 42)
                }
            }
        }
        
        guard let hd = edmFileData.edmFileHeader else {
            return rec
        }
        let numOfCyl = hd.config.features.numCylinders()
        let numOfEng = hd.config.numOfEngines()
        
        if numOfEng > 1 && numOfCyl > 6 {
            return rec
        }
        
        for i in 0..<numOfEng {
            var min = Int16(0x7fff)
            var max = Int16(-1)
            for j in 0..<numOfCyl {
                let idx = (j<6) ? (i*24 + j):(i+24-j)
                
                trc(level: .info, string: "i: \(i), j \(j), idx \(idx)")
                if !rec.naflags.hasBit(i: idx) {
                    if rdr.values[idx] > max {
                        max = rdr.values[idx]
                        trc(level: .info, string: "new max \(max)")
                    }
                    if rdr.values[idx] < min {
                        min = rdr.values[idx]
                        trc(level: .info, string: "new min \(min)")
                    }
                }
            }
            rec.diff[i] = Int(max) - Int(min)
        }
        
        rec.add(rawValue: rdr)
        let _ = readByte()
        return rec
    }
    
    
    mutating func parseFlightDecodeFlags() -> EdmDecodeFlags? {
        guard available > 1 else {
            return nil
        }
        
        let rv = Int16(data[nextread]) << 8 + Int16(data[nextread+1])
        let edmDecodeFlags = EdmDecodeFlags(rawValue: rv)
        nextread += 2
        return edmDecodeFlags
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
                trc(level: .error, string: "checksum error: " + String(cs ?? 0) + " != " + String(headerChecksum) + " (" + s + ")")
            }
            nextread += 2
            
            // read \n\r
            if self[nextread] != "\r" || self[nextread + 1] != "\n" {
                trc(level: .error, string: "invalid token at EOL " + String(self[nextread]))
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
            trc(level: .error, string: "invalid line type: \(linetypechar)")
        }
        trc(level: .info, string: "return new line, type: " + String(linetypechar))
        return hl
    }
    
    mutating func parseFlightHeaderAndSkip () -> EdmFlightHeader? {
        
        guard let flightheader = parseFlightHeader() else {
            return nil
        }
        
        guard nextFlightIndex! < edmFileData.edmFileHeader!.flightInfos.count else {
            trc(level: .error, string: "invalid flight index" + String(nextFlightIndex!))
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
    
    mutating func parseFlightHeaderAndBody (for id: UInt) {
        var currentRec = EdmFlightDataRecord()

        guard let flightheader = parseFlightHeader() else {
            self.invalid = true
            return
        }
        
        let flightId = flightheader.id
        let flags = flightheader.flags
        
        if (flightId != id) {
            trc(level: .warn, string: "Flight Ids dont match. Wanted \(id), found \(flightId)")
            self.invalid = true
            return
        }

        let features = self.edmFileData.edmFileHeader!.config.features
        if (flags.rawValue != features.rawValue){
            trc(level: .error, string: "flags dont match. flight " + flags.stringValue() + ", file " + features.stringValue())
//            self.invalid = true
//            return
        }

        let idx = nextFlightIndex!
        guard idx < edmFileData.edmFileHeader!.flightInfos.count else {
            trc(level: .warn, string: "invalid flight index" + String(idx))
            self.invalid = true
            return
        }
        
        let size = edmFileData.edmFileHeader!.flightInfos[idx].sizeBytes - 15
        let nextflightread = nextread + size
        
        if available < size {
            trc(level: .warn, string: "Not enough data (have \(available), need \(size)")
            self.invalid = true
            return
        }
        
        var efd = EdmFlightData()
        efd.flightHeader = flightheader
        
        guard let date = flightheader.date else {
            trc(level: .error,string:  "no date in header")
            self.invalid = true
            return
        }
        
        currentRec.date = date
        var interval_secs = TimeInterval(flightheader.interval_secs)
        
        while nextread + 3 <= nextflightread {
            let rec = parseFlightDataRecord(rec: currentRec)
            //rec.date = date
            
            var rc = rec.repeatCount
            while rc > 0 {
                efd.flightDataBody.append(currentRec)
                rc -= 1
            }
            
            if traceLevel.rawValue > EdmTracelevel.info.rawValue {
                trc(level: .info, string: rec.stringValue())
            }
            
            efd.flightDataBody.append(rec)
            currentRec = rec
            currentRec.repeatCount = 0
            if currentRec.mark == 2 {
                interval_secs = 1
            }
            
            if currentRec.mark == 3 {
                interval_secs = TimeInterval(flightheader.interval_secs)
            }
            currentRec.date = currentRec.date!.advanced(by: interval_secs)
        }
        
        edmFileData.edmFlightData.append(efd)

        trc(level: .info, string: "nextread is \(nextread), next flight starts at \(nextflightread), size is  \(size) ")

        
        nextread = nextflightread
        nextFlightIndex! += 1
        if nextFlightIndex == edmFileData.edmFileHeader!.flightInfos.count {
            complete = true
        }
        
        return
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
        //var efd = EdmFlightData()
        //efd.flightHeader = fh
        //edmFileData.edmFlightData.append(efd)
        
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

