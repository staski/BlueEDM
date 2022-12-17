//
//  FlightDetails.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 20.06.22.
//

import Foundation
import EdmParser

struct FlightPeakValue : Hashable, Codable {
    public var timeOffset : TimeInterval
    public var value : Int
}

struct FlightPeakInterval : Hashable, Codable {
    public var timeOffset : TimeInterval
    public var duration : TimeInterval
    public var value : Int
}

struct FlightDetails : Identifiable, Hashable, Codable {
    public var id : Int
    public var registration : String
    public var startTime : Date
    public var duration : TimeInterval
    public var fuelUsed : Double
    
    public var maxCht : FlightPeakValue
    public var maxEgt : FlightPeakValue
    public var maxOil : FlightPeakValue
    public var maxDiff : FlightPeakValue

    public var fuelFlowIntervalls = [FlightPeakValue]()
    public var chtWarnIntervalls = [FlightPeakValue]()
    public var egtWarnIntervalls = [FlightPeakValue]()
    public var oilLowIntervalls = [FlightPeakValue]()
    public var coldWarnIntervalls = [FlightPeakValue]()

    public init? ( for edmFlightData : EdmFlightData ){
        
        guard let fh = edmFlightData.flightHeader else {
            trc(level: .error, string: "init Flight Details: no header")
            return nil
        }
        
        id = Int(fh.id)
        registration = fh.registration
        
        guard let s = fh.date else {
            trc(level: .error, string: "init Flight Details: no start time (id = \(id))")
            return nil
        }
        startTime = s
        
        duration = edmFlightData.duration
        fuelUsed = edmFlightData.getFuelUsed(outFuelUnit: nil)

        var (idx, maxt) = edmFlightData.getMaxCht()
        var fr = edmFlightData.flightDataBody[idx]
        guard let t = fr.date else {
            trc(level: .error, string: "FlightData.stringValue(): no date set")
            return nil
        }
        var d = t.timeIntervalSince(fh.date!)
        maxCht = FlightPeakValue(timeOffset: d, value: maxt)
 
        (idx, maxt) = edmFlightData.getMaxEgt()
        fr = edmFlightData.flightDataBody[idx]
        guard let t = fr.date else {
            trc(level: .error, string: "FlightData.stringValue(): no date set")
            return nil
        }
        d = t.timeIntervalSince(fh.date!)
        maxEgt = FlightPeakValue(timeOffset: d, value: maxt)
        
        
        (idx, maxt) = edmFlightData.getMaxOil()
        fr = edmFlightData.flightDataBody[idx]
        guard let t = fr.date else {
            trc(level: .error, string: "FlightData.stringValue(): no date set")
            return nil
        }
        d = t.timeIntervalSince(fh.date!)
        maxOil = FlightPeakValue(timeOffset: d, value: maxt)
        
        
        (idx, maxt) = edmFlightData.getMaxDiff()
        fr = edmFlightData.flightDataBody[idx]
        guard let t = fr.date else {
            trc(level: .error, string: "FlightData.stringValue(): no date set")
            return nil
        }
        d = t.timeIntervalSince(fh.date!)
        maxDiff = FlightPeakValue(timeOffset: d, value: maxt)

    }
}
