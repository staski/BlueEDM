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
        
        
        return h != 0 ? String(format: "%d h %2.2d m", h ,m) : String(format: "%d m", m)
    }
}

typealias EdmFlightDetailViewItem = EdmFileListItem

struct EdmFlightDetailView: View {
    var id : Int
    var data : Data
    
    var p : EdmFileParser
    var h : EdmFileHeader?
    var fh : [EdmFlightHeader]
    var c : Int
    var fd : EdmFlightData?
    var datestring : String = ""
    var durationstring : String = ""
    var fuelusedstring : String = ""
    var maxchtstring : String = ""
    var maxegtstring : String = ""
    var f_unit_string : String = ""
    
    init (data: Data, id: Int) {
        self.data = data
        self.id = id
        p = EdmFileParser(data: data)
        h = p.parseFileHeaders()
        fh = [EdmFlightHeader]()
        c = h != nil ? h!.flightInfos.count : 0
        
        if h == nil {
            fh = [EdmFlightHeader]()
            return
        }
        
        p.edmFileData.edmFileHeader = h
        p.parseFlightHeaderAndBody(for: id)
        if p.invalid == true {
            trc(level: .error, string: "EdmFlightDetailView(\(data),\(id)): parser invalid state")
            return
        }
        
        fd = p.edmFileData.edmFlightData[0]
        guard fd != nil else {
            trc(level: .error, string: "EdmFlightDetailView(\(data),\(id)): invalid flightdata")
            return
        }
        
        datestring = fd!.flightHeader?.date?.toString() ?? ""
        durationstring = fd!.duration.hm()
        
        return
    }
    
    func getMaxString(param: String, getmax: (() -> (Int, Int))?) -> Text? {
        guard let gm = getmax else {
            trc(level: .error, string: "getMaxCht() returned nil")
            return nil
        }
        
        let (idx, m) = gm()
        guard let dt = fd!.flightDataBody[idx].date else {
            trc(level: .error, string: "no date for idx \(idx)")
            return nil
        }
        
        guard let dt2 = fd!.flightHeader?.date else {
            trc(level: .error, string: "no date in header")
            return nil
        }
        
        let d = dt.timeIntervalSince(dt2)
        return Text("max " + param + " \(m)° F after " + d.hm())
 
    }

    func getWarnIntervals(param: String, getinterval: () -> [(Int, Int, Int)]?) -> [String] {
        
        let a = getinterval()?.map() { (idx, duration, value) -> String in
            
            guard let dt = fd?.flightDataBody[idx].date else {
                return ""
            }
            
            guard let dt2 = fd!.flightHeader?.date else {
                trc(level: .error, string: "no date in header")
                return ""
            }
            
            let d = dt.timeIntervalSince(dt2)
            return param + " above " + String(value) + "° F after " + d.hms() + " for " + String(duration) + " seconds"
        }
        return a!
    }

    var body: some View {
        List {
            let ffunit = fd?.flightHeader?.ff.getUnit()
            let ffused_string = String(format: "%6.1f %@", fd!.getFuelUsed(outFuelUnit: ffunit), ffunit?.volumename ?? "")
            if #available(iOS 15.0, *) {
                Section (header: EdmFlightDetailViewItem(name: "Flight id: " + String(id), value: datestring)){
                    EdmFlightDetailViewItem(name: "Duration", value: durationstring)
                    EdmFlightDetailViewItem(name: "Fuel used", value: ffused_string)
                    getMaxString(param: "CHT", getmax: fd?.getMaxCht) ?? Text("")
                    getMaxString(param: "EGT", getmax: fd?.getMaxEgt) ?? Text("")
                    getMaxString(param: "DIF", getmax: fd?.getMaxDiff) ?? Text("")
                }.headerProminence(.increased)
                Section(header: Text("Warnings")){
                    if let a = getWarnIntervals(param: "CHT", getinterval: fd!.getChtWarnIntervals) {
                        ForEach(a) { s in
                            Text(s)
                        }
                    }
                }
            } else {
                Section (header: Text("Flight id: " + String(id))){
                    EdmFlightDetailViewItem(name: "Flight id" + String(id), value: datestring)
                    EdmFlightDetailViewItem(name: "Duration", value: durationstring)
                    EdmFlightDetailViewItem(name: "Fuel used", value: ffused_string)
                    getMaxString(param: "CHT", getmax: fd?.getMaxCht) ?? Text("")
                    getMaxString(param: "EGT", getmax: fd?.getMaxEgt) ?? Text("")
                    getMaxString(param: "DIF", getmax: fd?.getMaxDiff) ?? Text("")
                }
            }
        }
    }
}

struct EdmFlightDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EdmFlightDetailView(data: Data(), id: 0)
    }
}
