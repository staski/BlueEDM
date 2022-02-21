//
//  EdmFlightData.swift
//  EdmTools
//
//  Created by Staszkiewicz, Carl Philipp on 17.01.22.
//

import Foundation

struct BitArray16 : OptionSet {
    let rawValue: Int16
    let numberOfBits = 16
    var numberOfBytes : Int {
        return numberOfBits / 8
    }
    
    init(rawValue: Int16) {
            self.rawValue = rawValue
    }
    
    func hasBit(i : Int) -> Bool {
        if i < 0 || i > 15 {
            return false
        }
        if self.contains(BitArray16(rawValue: 1 << i)) {
            return true
        } else {
            return false
        }
    }
}

struct BitArray48: OptionSet, Codable {
    var rawValue: Int64
    let numberOfBits = 48
    var numberOfBytes : Int {
        return numberOfBits / 8
    }
    
    init(rawValue: Int64) {
            self.rawValue = rawValue
    }

    func hasBit(i : Int) -> Bool {
        if i < 0 || i > 47 {
            return false
        }
        if self.contains(BitArray48(rawValue: 1 << i)) {
            return true
        } else {
            return false
        }
    }
    
    mutating func setBit(i : Int) {
        if i < 0 || i > 47 {
            return
        }
        self.rawValue |= Int64(1 << i)
    }

    mutating func clearBit(i : Int) {
        if i < 0 || i > 47 {
            return
        }
        self.rawValue &= ~Int64(1 << i)
    }

}

typealias EdmNAFlags = BitArray48
typealias EdmValueFlags = BitArray48
typealias EdmSignFlags = BitArray48

typealias EdmDecodeFlags = BitArray16
typealias EdmScaleFlags = BitArray16

struct EdmRawDataRecord {
    var decodeFlags : EdmDecodeFlags?
    var repeatCount : Int8 = 0
    var valueFlags = EdmValueFlags()
    var scaleFlags = EdmScaleFlags()
    var signFlags = EdmSignFlags()
    
    var values : [Int16] = Array(repeating: 0, count: 48)
    var signValues : [Int] = Array(repeating: 1, count: 48)
    var scaleValues : [Int16] = Array(repeating: 0, count: 16)
    
    var checksum : UInt8 = 0
}

enum hp_or_rt1 : Codable {
    case hp(Int16)
    case rt1(Int16)
}

enum rpmhi_or_rcdt : Codable {
    case rpmhi(Int16)
    case rcdt(Int16)
}


struct EdmFlightDataRecord : Codable {
    var date : Date?
    var egt : [Int16] =  Array(repeating: 0x00f0, count: 6) //[0x00f0, 0x00f0]
    var t1 : Int16 = 0x00f0
    var t2 : Int16 = 0x00f0
    
    var cht : [Int16] = Array(repeating: 0x00f0, count: 6)
    var cld : Int16 = 0x00f0
    var oil : Int16 = 0x00f0
    
    var mark : Int16 = 0x00f0
    var unk_3_1 : Int16 = 0x00f0
    var cdt : Int16 = 0x00f0
    var iat : Int16 = 0x00f0
    var bat : Int16 = 0x00f0
    var oat : Int16 = 0x00f0
    var usd : Int16 = 0x00f0
    var ff  : Int16 = 0x00f0
    
    var regt : [Int16] = Array(repeating: 0x00f0, count: 6)
    var hprtl : hp_or_rt1 = hp_or_rt1.hp(0x00f0)
    var rt2 : Int16 = 0x00f0
    
    var rcht : [Int16] = Array(repeating: 0x00f0, count: 6)
    var rcld : Int16 = 0x00f0
    var roil : Int16 = 0x00f0
    
    var map : Int16 = 0x00f0
    var rpm : Int16 = 0x00f0
    var rpmhircdt : rpmhi_or_rcdt = rpmhi_or_rcdt.rpmhi(0x00f0)
    var riat : Int16 = 0x00f0
    var unk_6_4 : Int16 = 0x00f0
    var unk_6_5 : Int16 = 0x00f0
    var rusd : Int16 = 0x00f0
    var rff : Int16 = 0x00f0
    
    var diff : [Int] = [0,0]
    var naflags : EdmNAFlags = EdmNAFlags(rawValue: 0)
    
    var repeatCount : Int = 0
    func info () -> String {
        return "Edm Flight-Data Body"
    }
    
    func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encode(ff, forKey: .ff)
            try container.encode(usd, forKey: .usd)
            try container.encode(mark, forKey: .mark)
            try container.encode(egt, forKey: .egt)
            try container.encode(cht, forKey: .cht)
            try container.encode(cld, forKey: .cld)
            try container.encode(bat, forKey: .bat)
            try container.encode(diff[0], forKey: .diff)
    }
    
    func minEncode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(ff, forKey: .ff)
        try container.encode(usd, forKey: .usd)
        try container.encode(mark, forKey: .mark)

    }
    
    enum CodingKeys : String, CodingKey {
        case date = "Date"
        case ff = "Fuel Flow"
        case usd = "Fuel Used"
        case mark = "Mark"
        case bat = "Battery Voltage"
        case egt = "EGT"
        case cld = "Cold Warning"
        case cht = "CHT"
        case diff = "Maximal EGT difference"
    }
    
    func stringValue() -> String {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        encoder.dateEncodingStrategy = .formatted(formatter)
        encoder.outputFormatting = .prettyPrinted

        //todo
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? " --invalid record-- "
    }
    
    mutating func add (rawValue : EdmRawDataRecord) {
        for i in (0...5) {
            egt[i] += Int16(rawValue.values[i])
        }
        t1 += Int16(rawValue.values[6])
        t2 += Int16(rawValue.values[7])
        
        for i in (0...5) {
            cht[i] += Int16(rawValue.values[8+i])
        }
        
        cld += Int16(rawValue.values[14])
        oil += Int16(rawValue.values[15])
        
        mark += Int16(rawValue.values[16])
        unk_3_1 += Int16(rawValue.values[17])
        cdt += Int16(rawValue.values[18])
        iat += Int16(rawValue.values[19])
        bat += Int16(rawValue.values[20])
        oat += Int16(rawValue.values[21])
        usd += Int16(rawValue.values[22])
        ff  += Int16(rawValue.values[23])
        

        for i in (0...5) {
            regt[i] += Int16(rawValue.values[24+i])
        }
        
        switch hprtl.self {
            case .hp(var hpval) : hpval += Int16(rawValue.values[30])
            case .rt1(var rt1val) : rt1val += Int16(rawValue.values[30])
        }
                              
        rt2 += Int16(rawValue.values[31])

        for i in (0...5) {
            rcht[i] += Int16(rawValue.values[32+i])
        }

        rcld  += Int16(rawValue.values[38])
        roil  += Int16(rawValue.values[39])
        map  += Int16(rawValue.values[40])
        rpm  += Int16(rawValue.values[41])

        switch rpmhircdt.self {
            case .rpmhi(var rpmhival) : rpmhival += Int16(rawValue.values[42])
            case .rcdt(var rcdtval) : rcdtval += (rawValue.signFlags.hasBit(i: 42) ? -1 : 1) * Int16(rawValue.values[42])
        }

        riat  += Int16(rawValue.values[43])
        unk_6_4  += Int16(rawValue.values[44])
        unk_6_5  += Int16(rawValue.values[45])
        rusd  += Int16(rawValue.values[46])
        rff  += Int16(rawValue.values[47])

        repeatCount += Int(rawValue.repeatCount)
        return
    }
}

struct EdmFlightData : Encodable {
    var flightHeader : EdmFlightHeader?
    var flightDataBody : [EdmFlightDataRecord] = []
    
    func valid () -> Bool {
        if flightHeader == nil || flightDataBody.count < 1 {
            return false
        }
        
        return true
    }
    
    var duration : TimeInterval {
    
        if self.valid() == false {
            return TimeInterval()
        }
        
        guard let d1 = flightDataBody.first!.date else {
            return TimeInterval()
        }
        guard let d2 = flightDataBody.last!.date else {
            return TimeInterval()
        }
        
        return DateInterval(start: d1, end: d2).duration
    }
    
    var fuelUsed : Int {
        if self.valid() == false {
            return -1
        }
        
        return Int(flightDataBody.last!.usd) - Int(flightDataBody.first!.usd)
    }
    
    var maxEgt : (Int, Int) {
        
        var maxEgt : Int = 0
        var maxIdx : Int = 0
        
        if self.valid() == false {
            return (0,0)
        }
        
        for idx in 0..<flightDataBody.count {
            flightDataBody[idx].egt.forEach { e in
                if Int(e) > maxEgt {
                    maxEgt = Int(e)
                    maxIdx = idx
                }
            }
        }
        
        return (maxEgt, maxIdx)
    }

    var maxCht : (Int, Int) {
        
        var maxCht : Int = 0
        var maxIdx : Int = 0
        
        if self.valid() == false {
            return (0,0)
        }
        
        for idx in 0..<flightDataBody.count {
            flightDataBody[idx].cht.forEach { c in
                if Int(c) > maxCht {
                    maxCht = Int(c)
                    maxIdx = idx
                }
            }
        }
        
        return (maxCht, maxIdx)
    }

    enum CodingKeys : CodingKey {
        case flightHeader
        case flightDataBody
    }
    
    func stringValue() -> String? {
        guard let fh = flightHeader else {
            return nil
        }
        
        var s = fh.stringValue()
        s.append("duration: " + duration.hms() + ", fuel used: \(fuelUsed)")
        return s
    }
}

extension TimeInterval {
    func hms () -> String {
        var m = Int(self / 60.0)
        let s = Int(self) - m * 60
        let h = Int(Double(m) / 60.0)
        m = m - h * 60
        
        return String(format: "%dh %dm %ds", h,m,s)
    }
}
