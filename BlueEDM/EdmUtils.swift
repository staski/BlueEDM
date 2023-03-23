//
//  EdmUtils.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 21.03.23.
//

import Foundation

extension Date {
    func toString() -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: self)
    }
}

extension TimeInterval {
    public func hm () -> String {
        var m = Int(self / 60.0)
        let h = Int(Double(m) / 60.0)
        m = m - h * 60
        if self < 60.0 {
            return "start"
        }
        //return h != 0 ? String(format: "%dh %2.2dm", h ,m) : String(format: "%d m", m)
        return h != 0 ? String(format: "%2.2d:%2.2d", h ,m) : String(format: "00:%2.2d", m)
    }
    
    public func durationrelative() -> String {
        var str : String
        if self < 60.0 {
            return String("less than a minute")
        }
        var m = Int(self / 60.0)
        let h = Int(Double(m) / 60.0)
        m = m - h * 60
        let hunit = h < 2 ? "hour" : "hours"
        let munit = m < 2 ? "minute" : "minutes"
        if h != 0 {
            let str1 = String(format: "%2.2d", m)
            str = String("\(h) \(hunit) \(str1) \(munit)")
        } else {
            str = String(format: "%d", m).appending(" \(munit)")
        }
        return str
    }
}

