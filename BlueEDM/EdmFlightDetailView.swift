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

class EdmFileDetails : NSObject {
    var p : EdmFileParser
    
    init?(data: Data) {
        p = EdmFileParser(data: data)
        guard let header = p.parseFileHeaders() else {
            trc(level: .warn, string: "EdmFlightDetails init: error parsing file header")
            return nil
        }
        
        p.edmFileData.edmFileHeader = header

        for i in 0..<header.flightInfos.count
        {
            if p.complete == true {
                trc(level: .error, string: "EdmFlightDetails init: complete before parsing flight \(i)")
                return nil
            }
            if p.invalid == true {
                trc(level: .error, string: "EdmFlightDetails init: error parsing flight \(i)")
                return nil
            }
            
            let id = header.flightInfos[i].id
            p.parseFlightHeaderAndBody(for: id)
        }
    }
}

class EdmFlightDetails : NSObject {
    var p : EdmFileParser
    var h : EdmFileHeader
    var fh : [EdmFlightHeader]
    var fd : EdmFlightData
    var units : EdmUnits = EdmUnits()
    
    init?(data: Data, id: Int) {
        p = EdmFileParser(data: data)
        guard let header = p.parseFileHeaders() else {
            trc(level: .warn, string: "EdmFlightDetails init: error parsing file header")
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
        
        // units has the correct default for all other dimensions
        switch  h.ff.getUnit() {
        case .GPH:
            units.flow_unit = .gph
            units.volume_unit = .gallons
        case .KPH:
            units.flow_unit = .kgph
            units.volume_unit = .kg
        case .PPH:
            units.flow_unit = .lbsph
            units.volume_unit = .lbs
        case .LPH:
            units.flow_unit = .lph
            units.volume_unit = .liters
        }
        
        if h.config.temperatureUnit == .celsius {
            units.temp_unit = .celsius
        }
    }
    
    func getPeak(_ kind: EdmFlightPeakValue) -> (Int, Int)? {
        if !self.fd.hasfeature(kind.feature){
            return nil
        }
        
        return kind.getPeak(for: self.fd)?() // possibly nil
    }
    
    func getPeakString(_ idx: Int, for val: Int) -> (String, String)? {
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
}
    
class EdmFileDetailsJSON : UIActivityItemProvider {
    let url : URL
    let shareUrl : URL
    
    init(url: URL){
        self.url  = url
        var tmpname = url.deletingPathExtension().lastPathComponent
        let appendit = ".json"
        tmpname.append(appendit)

        self.shareUrl = URL(fileURLWithPath: NSTemporaryDirectory() + tmpname)
        super.init(placeholderItem: shareUrl)
    }
    
    override var item: Any {
        get {
            guard let  d = FileManager.default.contents(atPath: self.url.path) else {
                trc(level: .error, string: "EdmFlightDetailsShared.item: no data found at \(url.path)")
                return shareUrl
            }

            trc(level: .info, string: "EdmFileDetailsJSON: read \(self.url.path)")

            guard let e = EdmFileDetails(data: d) else {
                trc(level: .error, string: "EdmFlightDetailsShared.item: invalid file \(self.url.path)")
                return shareUrl
            }
            let encoder = JSONEncoder()
            let formatter = DateFormatter()

            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            encoder.dateEncodingStrategy = .formatted(formatter)
            encoder.outputFormatting = .prettyPrinted

            do {
                let data = try encoder.encode(e.p.edmFileData)
                try data.write(to: shareUrl)
            } catch {
                trc(level: .error, string: "EdmFlightDetailsShared.item: encoding error \(error)")
            }
            
            return shareUrl
        }
    }
}

class EdmFlightDetailsJSON : UIActivityItemProvider {
    let url : URL
    let shareUrl : URL
    let id : Int
    
    init(url: URL, id: Int){
        self.url  = url
        var tmpname = url.deletingPathExtension().lastPathComponent
        let appendit = "_" + String(id) + ".json"
        tmpname.append(appendit)

        self.shareUrl = URL(fileURLWithPath: NSTemporaryDirectory() + tmpname)
        self.id = id

        trc(level: .info, string: "EdmFlightDetailsShare: temp is \(shareUrl.path)")
        trc(level: .info, string: "EdmFlightDetailsShare: orig is \(url.path)")

        super.init(placeholderItem: shareUrl)
    }
    
    override var item: Any {
        get {
            guard let  d = FileManager.default.contents(atPath: url.path) else {
                trc(level: .error, string: "EdmFlightDetailsShared.item: no data found at \(url.path)")
                return shareUrl
            }
            guard let e = EdmFlightDetails(data: d, id: id) else {
                trc(level: .error, string: "EdmFlightDetailsShared.item: invalid file \(url.path)")
                return shareUrl
            }
            let encoder = JSONEncoder()
            let formatter = DateFormatter()

            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            encoder.dateEncodingStrategy = .formatted(formatter)
            encoder.outputFormatting = .prettyPrinted

            do {
                let data = try encoder.encode(e.fd)
                try data.write(to: shareUrl)
            } catch {
                trc(level: .error, string: "EdmFlightDetailsShared.item: encoding error \(error)")
            }
            
            return shareUrl
        }
    }
}

typealias EdmFlightDetailViewItem = EdmFileListItem

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

struct EdmFlightAlarm {
    let peakValue : EdmFlightPeakValue
    let edmFlightDetail : EdmFlightDetails
    let alarmValues : [(Int,Int,Int)]
    
    var alarmValue : Int {
        return alarmValues[0].2
    }
    
    init?(p: EdmFlightPeakValue, d: EdmFlightDetails) {
        peakValue = p
        edmFlightDetail = d
        
        guard let a = p.getWarnIntervalls(for: d.fd)() else {
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
                Section(header: Text("Warnings")){
                    EdmFlightAlarmView(p: .CHT, d: d)
                    if fd.hasfeature(.oil){
                        EdmFlightAlarmView(p: .OILLOW, d: d)
                    }
                    EdmFlightAlarmView(p: .DIFF, d: d)
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
