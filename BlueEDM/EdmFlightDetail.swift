//
//  SwiftUIView.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 09.12.22.
//

import SwiftUI
import EdmParser

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

