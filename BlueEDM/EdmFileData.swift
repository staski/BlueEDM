//
//  File.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 11.10.21.
//

import Foundation

struct EdmAlarmLimits : Encodable {
    var voltsHi     : Int = 0
    var voltsLow    : Int = 0
    var diff        : Int = 0
    var cht         : Int = 0
    var cld         : Int = 0
    var tit         : Int = 0
    var oilHi       : Int = 0
    var oilLow      : Int = 0
    
    init (_ values: [String] = []){
        if values.count != 8 {
            voltsHi = 0
            voltsLow = 0
            diff = 0
            cht  = 0
            cld = 0
            tit = 0
            oilHi = 0
            oilLow = 0
        } else {
            voltsHi = Int(values[0]) ?? 0
            voltsLow = Int(values[1]) ?? 0
            diff = Int(values[2]) ?? 0
            cht  = Int(values[3]) ?? 0
            cld = Int(values[4]) ?? 0
            tit = Int(values[5]) ?? 0
            oilHi = Int(values[6]) ?? 0
            oilLow = Int(values[7]) ?? 0
        }
    }
    
    func stringValue() -> String  {
        var str = ""
        str.append("Alarm Thresholds: ")
        str.append("Volts Hi: " + String(voltsHi))
        str.append(", Volts Low: " + String(voltsLow))
        str.append(", Diff: " + String(diff))
        str.append(", CHT: " + String(cht))
        str.append(", CLD: " + String(cld))
        str.append(", TIT: " + String(tit))
        str.append(", Oil High: " + String(oilHi))
        str.append(", Oil Low: " + String(oilLow))

        str.append("\n")
        
        return str
    }
}

enum FuelFlowUnit : Encodable {
    case GPH // Gallon per hour
    case KPH // Kilogram per hour
    case LPH // Liter per hour
    case PPH // Pound per hour

    var name: String {
        get { return String(describing: self) }
    }

}

struct EdmFuelFlow : Encodable {
    var fuelFlow        : FuelFlowUnit = .LPH
    var ftank1 : Int , ftank2 : Int
    var k1, k2          : Int

    init (_ values: [String] = []){
        fuelFlow = .LPH
        ftank1 = 0; ftank2 = 0; k1 = 0; k2 = 0
        if values.count == 5 {
            ftank1 = Int(values[1]) ?? 0
            ftank2 = Int(values[2]) ?? 0
            k1 = Int(values[3]) ?? 0
            k2 = Int(values[4]) ?? 0
            
            let v = Int(values[0]) ?? 0
            switch v {
            case 0:
                fuelFlow = .GPH
            case 1:
                fuelFlow = .PPH
            case 2:
                fuelFlow = .LPH
            case 3:
                fuelFlow = .KPH
            default:
                break
            }
        }
    }
    
    func stringValue() -> String {
        var str = ""
        str.append("Fuel Flow Units: " + fuelFlow.name)
        str.append(", capacity1: " + String(ftank1))
        str.append(", capacity2: " + String(ftank2))
        str.append(", k1: " + String(k1) + ", k2: " + String(k2))
        str.append("\n")
        
        return str
    }
}

// -m-d fpai r2to eeee eeee eccc cccc cc-b
struct EdmFeatures : OptionSet, Encodable {
    let rawValue: UInt32
    
    static let battery = EdmFeatures(rawValue: (1<<0))
    static let oil = EdmFeatures(rawValue: (1<<20))
    static let tit = EdmFeatures(rawValue: (1<<21))
    static let tit2 = EdmFeatures(rawValue: (1<<22))
    static let carb = EdmFeatures(rawValue: (1<<23))
    static let temp = EdmFeatures(rawValue: (1<<24))
    static let rpm = EdmFeatures(rawValue: (1<<25))
    static let ff = EdmFeatures(rawValue: (1<<27))
    static let cld = EdmFeatures(rawValue: (1<<28))
    static let map = EdmFeatures(rawValue: (1<<30))

    static let c = [
        EdmFeatures(rawValue: (1<<2)),
        EdmFeatures(rawValue: (1<<3)),
        EdmFeatures(rawValue: (1<<4)),
        EdmFeatures(rawValue: (1<<5)),
        EdmFeatures(rawValue: (1<<6)),
        EdmFeatures(rawValue: (1<<7)),
        EdmFeatures(rawValue: (1<<8)),
        EdmFeatures(rawValue: (1<<9)),
        EdmFeatures(rawValue: (1<<10)),
    ]
    
    static let e = [
        EdmFeatures(rawValue: (1<<11)),
        EdmFeatures(rawValue: (1<<12)),
        EdmFeatures(rawValue: (1<<13)),
        EdmFeatures(rawValue: (1<<14)),
        EdmFeatures(rawValue: (1<<15)),
        EdmFeatures(rawValue: (1<<16)),
        EdmFeatures(rawValue: (1<<17)),
        EdmFeatures(rawValue: (1<<18)),
        EdmFeatures(rawValue: (1<<19)),
    ]
    
    init(rawValue: UInt32) {
            self.rawValue = rawValue
    }
    
    init (high: UInt16,low: UInt16){
        self.rawValue = (UInt32(high)<<16) + UInt32(low)
    }
    
    func numCylinders() -> Int {
        var count = 0
        
        for i in EdmFeatures.c {
            if self.contains(i) {
                count += 1
            }
        }

        return count
    }
    
    func stringValue () -> String {
        var str = ""
        str.append("Sensors: ")
        str.append(String(numCylinders()) + " cylinders")
        if self.contains(.battery){
            str.append(", battery")
        }
        if self.contains(.oil) {
            str.append(", oil")
        }
        if self.contains(.tit) {
            str.append(", tit")
        }
        if self.contains(.tit2) {
            str.append(", tit2")
        }
        if self.contains(.carb) {
            str.append(", carb")
        }
        if self.contains(.temp) {
            str.append(", temp")
        }
        if self.contains(.rpm) {
            str.append(", rpm")
        }
        if self.contains(.ff) {
            str.append(", fuelflow")
        }
        if self.contains(.cld) {
            str.append(", cld")
        }
        if self.contains(.map) {
            str.append(", map")
        }

        str.append("\n")
        
        return str
    }
}


struct EdmConfig : Encodable {
    var modelNumber : Int = 0
    var flagsLow : UInt16 = 0, flagsHi : UInt16 = 0
    var unknown : Int = 0
    var version : Int = 0
    var features =  EdmFeatures(rawValue: 0)
    
    init (_ values: [String] = []) {
        if values.count != 5 {
            return
        }
        
        modelNumber = Int(values[0]) ?? -1
        flagsLow = UInt16(values[1]) ?? 0
        flagsHi = UInt16(values[2]) ?? 0
        unknown = Int(values[3]) ?? -1
        version = Int(values[4]) ?? -1
        features = EdmFeatures(high: flagsHi, low: flagsLow)
    }
    
    func numOfEngines () -> Int {
        if modelNumber == 760 {
            return 2
        }
        return 1
    }
    
    func hasRPM () -> Bool {
        return false
    }
    func stringValue () -> String {
        var str = ""
        str.append("Model: EDM" + String(modelNumber))
        str.append(", SW-Version: " + String(version) + "\n")

        return str
    }
}

struct EdmFileHeader : Encodable {
    var registration : String = ""
    var date : Date?
    var alarms = EdmAlarmLimits()
    var ff = EdmFuelFlow()
    var config = EdmConfig()
    var flightInfos : [EdmFlightInfo] = []
    var headerLen = 0
    var totalLen = 0
    
    func initDate(_ values: [String]) -> Date? {
        if values.count != 6 {
            return nil
        }
        
        let month = Int(values[0]) ?? 0
        let day = Int(values[1]) ?? 0
        let year = (Int(values[2]) ?? 0) + 2000
        let hour = Int(values[3]) ?? 0
        let minutes = Int(values[4]) ?? 0
        
        let dc = DateComponents(year: year, month: month, day: day, hour: hour, minute: minutes)
        let c = Calendar(identifier: Calendar.Identifier.gregorian)
        let d = c.date(from: dc)
        
        return d
    }
    
    func initRegistration (_ values: [String]) -> String? {
        if values.count != 1 {
            return nil
        }
        let r = values[0]
        return r
    }
    
    func stringValue(includeFlights: Bool) -> String {
        var str = ""
        str.append("Header Size: " + String(headerLen))
        str.append(", Total Size: " + String(totalLen) + "\n\n")
        str.append("Registration: " + registration + "\n")
        if date != nil {
            str.append("Download Date: " + date!.toString(dateFormat: "dd.MM.YY HH:mm\n"))
            //str.append("(offset: " + String(Int((self.timeOffset()/60.0))) + " minutes)\n")
        }
        str.append(config.stringValue())
        str.append(config.features.stringValue())
        str.append(ff.stringValue())
        str.append(alarms.stringValue())
        
        str.append("Flights:\n")
        if includeFlights {
            for flight in flightInfos {
                str.append(flight.stringValue())
            }
        }
        return str
    }
    
    func timeOffset () -> TimeInterval {
        return -Date().distance(to: self.date ?? Date())
    }
}

struct EdmFlightInfo : Encodable {
    var id : Int = 0
    var sizeWords : Int = 0
    
    var sizeBytes : Int {
        return sizeWords * 2
    }
    
    init(_ values: [String] = []){
        if values.count != 2 {
            return
        }
        
        id = Int(values[0]) ?? -1
        sizeWords = Int(values[1]) ?? -1
    }
    
    func stringValue() -> String {
        var str = ""
        str.append("Id: " + String(id) + ", Size: " + String(sizeBytes) + " Bytes\n")
        return str
    }
}

struct EdmFlightHeader : Encodable {
    var id : UInt16 = 0
    var flags = EdmFeatures()
    var unknown : UInt16 = 0
    var interval_secs : UInt16 = 0
    var date : Date?
    var checksum : Int8 = 0
    
    func stringValue () -> String {
        var str = ""
        
        let d : Date = date ?? Date()
        str.append("flight id: " + String(id))
        //str.append(", rate: " + String(interval_secs) + " secs")
        str.append(", " + d.toString(dateFormat: "dd.MM.YY HH:mm\n"))
        
        return str
    }
    
    init (values a : [UInt16], checksum : Int8 ){
       
    
        if a.count < 7 {
            return
        }
        
        id = a[0]
        flags = EdmFeatures(high: a[2], low: a[1])
        unknown = a[3]
        interval_secs = a[4]
        
        
        let dt = a[5]
        let tm = a[6]
        
        let day = Int(dt & 0x001F)
        let month = Int((dt & 0x01E0) >> 5)
        let year = Int((dt & 0xfe00) >> 9)
        
        let seconds = Int((tm & 0x001f)) * 2
        let minutes = Int((tm & 0x07E0) >> 5)
        let hour = Int((tm & 0xF800) >> 11)

        let dc = DateComponents(year: year, month: month, day: day, hour: hour, minute: minutes, second: seconds)
        let c = Calendar(identifier: Calendar.Identifier.gregorian)
        date = c.date(from: dc)
        
        self.checksum = checksum
    }
}

struct EdmFileData : Encodable {
    var edmFileHeader : EdmFileHeader?
    var edmFlightData : [EdmFlightData]
    init () {
        edmFlightData = []
    }
}

enum EdmTracelevel: Int {
    case error = 0
    case warn
    case info
    case all
}
var traceLevel : EdmTracelevel = .error

func trc(level: EdmTracelevel, string : @autoclosure () -> String) {
    if level.rawValue <= traceLevel.rawValue {
        print(string())
    }
}
