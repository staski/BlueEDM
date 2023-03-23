//
//  EdmFlightDetailView.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 11.12.22.
//

import SwiftUI
import EdmParser


typealias EdmFlightDetailViewItem = EdmFileListItem

// todo: move to EdmParser
extension Int {
    func exceeds(limit value: EdmFlightPeakValue, for header: EdmFlightHeader) -> Bool? {
        guard let val = value.getThresholdFor(header: header) else {
            return nil
        }
        switch value {
        case .CLD:
            return -self > val ? true : false
        case .OILLOW, .BATLOW, .OATLO:
            return self < val ? true : false
        default:
            return self > val ? true : false
        }
    }
}

struct EdmFlightPeakValueView : View {
    
    let peakValue : EdmFlightPeakValue
    let edmFlightDetail : EdmFlightDetails
    
    func getPeakValueString () -> (String,String, Color)? {
        var time_s : String, value_s : String
        let c : Color
        if let (idx, val) = edmFlightDetail.getPeak(peakValue),
            let (timeString, valueString) = edmFlightDetail.getPeakString(idx, for: val) {
            let s = peakValue.unit(for: edmFlightDetail.h).scale
            if s != 1 {
                value_s = String(format: "%4.1f", Double(val)/(Double(s)))
            } else {
                value_s = valueString
            }
            time_s = timeString
            c = getFontColor(for: val)
        } else {
            return nil
        }
        return (value_s, time_s, c)
    }
        
    func getFontColor(for value: Int) -> Color {
        guard let h = self.edmFlightDetail.fd.flightHeader else {
            trc(level: .error, string: "EdmFlightPeakValueView.getFontColor: no flight header")
            return Color.primary
        }
        guard let b = value.exceeds(limit: peakValue, for: h) else {
            return Color.primary
        }
        if b == true {
            return Color.red
        }
        return Color.green
    }
    
    var body: some View {
        let titleString = peakValue.longname
            
        GroupBox {
            VStack(alignment: .leading) {
                Text(titleString)
                if let (valueString, timeString, c) = self.getPeakValueString() {
                    Text(valueString + " " + peakValue.unit(for: edmFlightDetail.h).shortname).font(.system(size: 24, weight: .bold)).foregroundColor(c)
                    Text("after " + timeString).font(.caption)
                }
                 else {
                    Text("----").font(.system(size: 24, weight: .bold))
                    Text("not supported").font(.caption)
                }
            }.frame(minWidth: 100).padding(.horizontal,5)
        }
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
            trc(level: .info, string: "EdmFlightAlarmView: no alarm for \(peakValue.longname)")
            return
        }

        titleString = "\(peakValue.longname) \(peakValue.aboveOrBelow) \(alarms!.alarmValue) \(peakValue.unit(for: edmFlightDetail.h).shortname)"
    }
    
    var body: some View {
        if alarms != nil {
            VStack(alignment: .leading) {
                Text(titleString).frame(maxWidth: .infinity, alignment: .center)
                ForEach(alarms!.alarmValues, id: \.self.0) { (idx, duration, value ) in
                    
                    let dt = edmFlightDetail.fd.flightDataBody[idx].date!
                    let dt2 = edmFlightDetail.fd.flightHeader?.date!
                    let dur = dt.timeIntervalSince(dt2!)
                    
                    Text("after " + dur.hm() + " for " + TimeInterval(duration).durationrelative()).font(.caption)
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
    
    @State private var index = 0
    
    init (data: Data, id: Int) {
        self.data = data
        self.id = id
        
        details = EdmFlightDetails(data: data, id: id)
        guard let d = details else {
            trc(level: .info, string: "EdmFlightDetailView: No EdmFlightDetails available")
            return
        }
                
        datestring = d.fd.flightHeader?.date?.toString() ?? ""
        durationstring = d.fd.duration.hm()
        
        return
    }
    
    var body: some View {
        let d = details!
        let fd = d.fd
        var ffused_string : String = ""
        var availablePeakValues : [EdmFlightPeakValue] = []

        availablePeakValues = EdmFlightPeakValue.allCases.reduce(into: availablePeakValues, { (res, elem) in
            if elem.getPeak(for: d.fd) != nil && d.fd.hasfeature(elem.feature) {
                res.append(elem)
            }
        })

        if fd.hasfeature(.ff){
            ffused_string = String(format : "%6.1f %@", fd.getFuelUsed(outFuelUnit: nil), d.h.units.volume_unit.name)
        }
        
       let l = List {
                Section (header: EdmFlightDetailViewItem(name: "Flight id: " + String(id), value: datestring)){
                    EdmFlightDetailViewItem(name: "Duration", value: durationstring)
                    if fd.hasfeature(.ff){
                        EdmFlightDetailViewItem(name: "Fuel used", value: ffused_string)
                    }
                }
                Section(header: Text("Peak Values")){
                    let columns = [GridItem(.adaptive(minimum: 150))]
                    LazyVGrid(columns: columns, spacing: 20){
                        ForEach(availablePeakValues, id: \.self){ peakValue in
                            EdmFlightPeakValueView(peakValue: peakValue, edmFlightDetail: d)
                        }
                    }.padding(.vertical)
                }
                if (d.fd.hasnaflag){
                    Section(header: Text("Failed Sensors")){
                        EdmNAValuesView(d)
                    }
                }
                Section(header: Text("Warnings")){
                    EdmFlightAlarmView(p: .CHT, d: d)
                    if fd.hasfeature(.oil){
                        EdmFlightAlarmView(p: .OILHI, d: d)
                    }
                    if fd.hasfeature(.cld){
                        EdmFlightAlarmView(p: .CLD, d: d)
                    }
                    EdmFlightAlarmView(p: .DIFF, d: d)
                }
            }
        return l
    }
}

struct EdmNASingleNAValueView : View {
    let sensor: String
    let intervals: [String]
    
    var body: some View {
        let v = VStack {
            ForEach(intervals, id: \.self) { interval in
                Text(interval).font(.caption)
            }
        }
        return v
    }
}

struct EdmNAValuesView: View {
    let naintervals : EdmNAIntervals
    var textarray : [String] = []
    var details: EdmFlightDetails
    
    var allKeys : [String] {
        return naintervals.keys.sorted()//.map { String($0) }
    }
    
    func naintervalstrings(key: String) -> [String]? {
        var intervalstrings : [String] = []
        
        guard let interval = naintervals[key] else {
            return nil
        }
        
        let d = details
        
        for i in 0 ..< interval.count / 2 {
            guard let di1 = d.fd.flightDataBody[interval[2*i]].date else {
                intervalstrings.append("invalid date for \(interval[2*i])")
                continue
            }
            guard let header = d.fd.flightHeader else {
                intervalstrings.append("no flight header")
                continue
            }
            
            guard let ds = header.date else {
                intervalstrings.append("no start date for flight")
                continue
            }

            let start = di1.timeIntervalSince(ds)

            guard let di2 = d.fd.flightDataBody[interval[2*i+1]].date else {
                intervalstrings.append("invalid date for \(interval[2*i + 1])")
                continue
            }
            
            let duration = di2.timeIntervalSince(di1)
            
            intervalstrings.append("after \(start.hm()) for \(duration.durationrelative())")
        }
        
        return intervalstrings
        
    }
    
    init (_ d: EdmFlightDetails){
        details = d
        naintervals = d.fd.getNAIntervals()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(allKeys, id: \.self){ key in
                Text("Sensor " + key + " not available").frame(maxWidth: .infinity, alignment: .center)
                EdmNASingleNAValueView(sensor: key,
                                       intervals: naintervalstrings(key: key) ?? [])
            }
        }
    }
}

struct EdmFlightDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EdmFlightDetailView(data: Data(), id: 0)
    }
}
