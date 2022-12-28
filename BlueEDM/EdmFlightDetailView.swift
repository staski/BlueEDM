//
//  EdmFlightDetailView.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 11.12.22.
//

import SwiftUI
import EdmParser

extension TimeInterval {
    public func hm () -> String {
        var m = Int(self / 60.0)
        let h = Int(Double(m) / 60.0)
        m = m - h * 60
    
        return h != 0 ? String(format: "%dh %2.2dm", h ,m) : String(format: "%d m", m)
    }
}

class EdmFlightDetails : NSObject {
    var p : EdmFileParser
    var h : EdmFileHeader
    var fh : [EdmFlightHeader]
    var fd : EdmFlightData
    
    init?(data: Data, id: Int) {
        p = EdmFileParser(data: data)
        guard let header = p.parseFileHeaders() else {
            trc(level: .error, string: "EdmFlightDetails init: error parsing file header")
            return nil
        }
        h = header
        fh = [EdmFlightHeader]() // to be used when implemented in EdmFileList
        
        p.edmFileData.edmFileHeader = h
        p.parseFlightHeaderAndBody(for: id)
        if p.invalid == true {
            trc(level: .error, string: "EdmFlightDetailView(\(data),\(id)): parser invalid state")
            return nil
        }
        
        // todo: preallocate edmFlightData in the right size and insert at the correct position
        // (such that edmFileHeader.idx(for flightId) gives the correct index)
        fd = p.edmFileData.edmFlightData[0]
    }
    
    func getMaxString(_ kind: EdmFlightPeakValue) -> (String, String)? {
        let (idx, val) = kind.getMax(for: self)()
        guard let dt = self.fd.flightDataBody[idx].date else {
            trc(level: .error, string: "getMaxString: no date for idx \(idx)")
            return nil
        }
        
        guard let dt2 = self.fd.flightHeader?.date else {
            trc(level: .error, string: "getMaxString: no date in header")
            return nil
        }
        
        let d = dt.timeIntervalSince(dt2)
        return (d.hm(), String(val))
    }
    
    func getUnitString (_ unit: EdmFlightParamType) -> String {
        switch unit {
        case .FLOW:
            let ffunit = fd.flightHeader?.ff.getUnit()
            let ffused_string = String(format: "%6.1f %@", fd.getFuelUsed(outFuelUnit: ffunit), ffunit?.name ?? "flow unit")
            return ffused_string
        case .VOL:
            let ffunit = fd.flightHeader?.ff.getUnit()
            let ffused_string = String(format: "%6.1f %@", fd.getFuelUsed(outFuelUnit: ffunit), ffunit?.volumename ?? "volume unit")
            return ffused_string
        default:
            return "°F"
        }
    }
}

typealias EdmFlightDetailViewItem = EdmFileListItem

enum EdmFlightParamType {
    case VOL
    case TEMP
    case FLOW
}

enum EdmFlightPeakValue {
    case CHT
    case EGT
    case FF
    case CLD
    case DIFF
    case OIL
    
    public var longname : String {
        get {
            switch self {
            case .CHT:
                return "cylinder temperature"
            case .EGT:
                return "exhaust gas temperature"
            case .FF:
                return "maximum fuel flow"
            case .CLD:
                return "maximum cooling"
            case .DIFF:
                return "maximum difference"
            case .OIL:
                return "oil temperature"
            }
        }
    }

    public var unit : String {
        get {
            switch self {
            case .CHT, .EGT, .CLD,.DIFF,.OIL:
                return "°F"
            case .FF:
                return "l/h"
            }
        }
    }
    
    public var paramType : EdmFlightParamType {
        get {
            switch self {
            case .FF:
                return .FLOW
            default:
                return .TEMP
            }
        }
    }


    public var name: String {
        get { return String(describing: self) }
    }
    
    public func getMax(for edmFlightDetails : EdmFlightDetails) -> (() -> (Int, Int)) {
        switch self {
        case .CHT:
            return edmFlightDetails.fd.getMaxCht
        case .EGT:
            return edmFlightDetails.fd.getMaxEgt
        case .OIL:
            return edmFlightDetails.fd.getMaxOil
        case .DIFF:
            return edmFlightDetails.fd.getMaxDiff
        default:
            return edmFlightDetails.fd.getMaxOil
        }
    }
    
    public func getWarnIntervalls(for edmFlightDetails : EdmFlightDetails) -> (() -> [(Int, Int, Int)]?) {
        switch self {
        case .CHT:
            return edmFlightDetails.fd.getChtWarnIntervals
        case .EGT:
            return edmFlightDetails.fd.getChtWarnIntervals
        case .OIL:
            return edmFlightDetails.fd.getOilLowIntervals
        case .DIFF:
            return edmFlightDetails.fd.getDiffWarnIntervals
        default:
            return edmFlightDetails.fd.getColdWarnIntervals
        }
    }
}

struct EdmFlighPeakValueView : View {
    
    let peakValue : EdmFlightPeakValue
    let edmFlightDetail : EdmFlightDetails
    
    var body: some View {
        let titleString = "Maximum " + peakValue.name
        let (timeString, valueString) = edmFlightDetail.getMaxString(peakValue) ?? ("INVALID", "INVALID")

        let vs = VStack(alignment: .leading) {
            Text(titleString)
            Text(valueString + " " + edmFlightDetail.getUnitString(peakValue.paramType)).font(.system(size: 24, weight: .bold))
            Text("after " + timeString).font(.caption)
        }
        
        return vs
    }
}

struct EdmFlightAlarm {
    let peakValue : EdmFlightPeakValue
    let edmFlightDetail : EdmFlightDetails
    let alarmValues : [(Int,Int,Int)]
    
    var alarmValue : Int {
        return alarmValues[0].2
    }

    var aboveOrBelow : String {
        if peakValue == .OIL {
            return "below"
        }
        return "above"
    }
    
    init?(p: EdmFlightPeakValue, d: EdmFlightDetails) {
        peakValue = p
        edmFlightDetail = d
        
        guard let a = p.getWarnIntervalls(for: d)() else {
            return nil
        }
        
        if a.count == 0 {
            return nil
        }
        
        alarmValues = a
    }
}

struct EdmFlightAlarmView : View {
    let peakValue : EdmFlightPeakValue
    let edmFlightDetail : EdmFlightDetails
    let alarms : EdmFlightAlarm?
    var titleString : String = ""

    init(p: EdmFlightPeakValue, d: EdmFlightDetails) {
        peakValue = p
        edmFlightDetail = d
        
        alarms = EdmFlightAlarm(p: peakValue, d: edmFlightDetail)
        if alarms == nil {
            trc(level: .error, string: "EdmFlightAlarmView: no alarm for \(peakValue.longname)")
            return
        }

        titleString = "\(peakValue.name) \(alarms!.aboveOrBelow) \(alarms!.alarmValue) \(edmFlightDetail.getUnitString(peakValue.paramType))"
    }
    
    var body: some View {
        if alarms != nil {
            VStack(alignment: .leading) {
                Text(titleString).frame(maxWidth: .infinity, alignment: .center)
                ForEach(alarms!.alarmValues, id: \.self.0) { (idx, duration, value ) in
                    
                    let dt = edmFlightDetail.fd.flightDataBody[idx].date!
                    let dt2 = edmFlightDetail.fd.flightHeader?.date!
                    let dur = dt.timeIntervalSince(dt2!)
                    
                    Text("after " + dur.hm() + " for " + String(duration) + " seconds").font(.caption)
                }
            }
        }
    }
}

struct EdmFlightDetailView: View {
    var id : Int
    var data : Data
    
    var details : EdmFlightDetails?
    
    var c : Int = 0
    var fd : EdmFlightData?
    var datestring : String = ""
    var durationstring : String = ""
    var fuelusedstring : String = ""
    var maxchtstring : String = ""
    var maxegtstring : String = ""
    var f_unit_string : String = ""
    
    @State private var index = 0
    
    init (data: Data, id: Int) {
        self.data = data
        self.id = id
        
        details = EdmFlightDetails(data: data, id: id)
        guard let d = details else {
            trc(level: .error, string: "EdmFlightDetailView: No EdmFlightDetails available")
            return
        }
                
        datestring = d.fd.flightHeader?.date?.toString() ?? ""
        durationstring = d.fd.duration.hm()
        
        return
    }
    
    func getWarnIntervals(param: String, getinterval: () -> [(Int, Int, Int)]?) -> [String] {
        
        let a = getinterval()?.map() { (idx, duration, value) -> String in
            guard let d = details else {
                return ""
            }
            
            guard let dt = d.fd.flightDataBody[idx].date else {
                return ""
            }
            
            guard let dt2 = d.fd.flightHeader?.date else {
                trc(level: .error, string: "no date in header")
                return ""
            }
            
            let dur = dt.timeIntervalSince(dt2)
            return param + " above " + String(value) + "°F after " + dur.hm() + " for " + String(duration) + " seconds"
        }
        return a ?? ["INVALID"]
    }

    var body: some View {
        let d = details!
        let ffunit = d.fd.flightHeader?.ff.getUnit()
        let ffused_string = String(format: "%6.1f %@", d.fd.getFuelUsed(outFuelUnit: ffunit), ffunit?.volumename ?? "")

        let l = VStack {
            List {
                Section (header: EdmFlightDetailViewItem(name: "Flight id: " + String(id), value: datestring)){
                    EdmFlightDetailViewItem(name: "Duration", value: durationstring)
                    EdmFlightDetailViewItem(name: "Fuel used", value: ffused_string)
                }
                Section(header: Text("Peak Values")){
                    HStack {
                        EdmFlighPeakValueView(peakValue: .CHT, edmFlightDetail: d)
                        Spacer()
                        EdmFlighPeakValueView(peakValue: .EGT, edmFlightDetail: d)
                    }
                    HStack {
                        EdmFlighPeakValueView(peakValue: .OIL, edmFlightDetail: d)
                        Spacer()
                        EdmFlighPeakValueView(peakValue: .DIFF, edmFlightDetail: d)
                    }
                }
                Section(header: Text("Warnings")){
                    EdmFlightAlarmView(p: .CHT, d: d)
                    EdmFlightAlarmView(p: .OIL, d: d)
                    EdmFlightAlarmView(p: .DIFF, d: d)
                }
            }
        }
        return l
            
    }
}

struct EdmFlightDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EdmFlightDetailView(data: Data(), id: 0)
    }
}
