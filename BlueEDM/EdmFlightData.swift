//
//  File.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 11.10.21.
//

import Foundation
import ImageIO
import SwiftUI

struct EdmAlarmLimits {
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
}

enum FuelFlowUnit {
    case GPH // Gallon per hour
    case KPH // Kilogram per hour
    case LPH // Liter per hour
    case PPH // Pound per hour
}

struct EdmFuelFlow {
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
}

struct EdmConfig {
    var modelNumber : Int = 0
    var flagsLow : Int = 0, flagsHi : Int = 0
    var unknown : Int = 0
    var version : Int = 0
    var features =  EdmFeatures(rawValue: 0)
    
    init (_ values: [String] = []) {
        if values.count != 5 {
            return
        }
        
        modelNumber = Int(values[0]) ?? -1
        flagsLow = Int(values[1]) ?? -1
        flagsHi = Int(values[2]) ?? -1
        unknown = Int(values[3]) ?? -1
        version = Int(values[4]) ?? -1
        features = EdmFeatures(high: flagsHi, low: flagsLow)
    }
}


struct EdmFileData {
    var registration : String = ""
    var date : Date?
    var alarms = EdmAlarmLimits()
    var ff = EdmFuelFlow()
    var config = EdmConfig()
    var flightInfos : [EdmFlightData] = []

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
}

struct EdmFlightData {
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
}

// -m-d fpai r2to eeee eeee eccc cccc cc-b
struct EdmFeatures : OptionSet {
    let rawValue: Int
    
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
    
    init(rawValue: Int) {
            self.rawValue = rawValue
    }
    
    init (high: Int,low: Int){
        self.rawValue = (high<<16) + low
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
}
