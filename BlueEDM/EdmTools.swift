//
//  EdmTools.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 21.10.21.
//

import Foundation
import Foundation
import CoreImage

struct EdmDataStream {
    var data : Data
    var nextread  = 0
    var eor = false // signals end of record
    var checksum = 0
    
    var available : Int {
        return data.count - nextread
    }
    
    var values : [String] = []
    var item : String?

    init(_ data1: Data){
        data = data1
    }
    
    subscript(index: Data.Index) -> Character {
        return Character(Unicode.Scalar(data[index]))
    }
    
    mutating func readChar() -> Character {
        let c = self[nextread]
        //print ("read char: " + String(c) + " (" + String(Int(c.asciiValue ?? 0)) + ")")
        checksum ^= Int(c.asciiValue ?? 0)
        nextread += 1
        return c
    }
    
    mutating func nextItem () -> String? {
        var c : Character
        var newItem : String?
        var skip = false
        
        while available > 0 {
            c = readChar()

            if (c == ","){
                return newItem
            }
            if (c == "*"){
                eor = true
                print("new Item: " + (newItem ?? "nil"))
                return newItem
            }

            if (c.isLetter || c.isNumber){
                if skip {
                    continue
                }
                
                //print("found letter: " + String(c))
                if (newItem == nil){
                    newItem = String(c)
                } else {
                    newItem!.append(String(c))
                }
            } else if (c.isASCII || c.isWhitespace){
                if newItem != nil {
                    skip = true
                }
            }
        }

        return String()
    }
    
    mutating func parseHeaderLine () -> EdmHeaderLine {
        var hl : EdmHeaderLine = EdmHeaderLine()
        var linetypechar : Character = Character("I")
        eor = false
        
        if available > 1 {
            if self[0] != "$" {
                return hl
            }
            nextread += 1
            linetypechar = readChar()
        }
        
        while available > 0 && eor == false {
            item = nextItem()
            if item != nil {
                hl.contents.append(item!)
            }
        }
        
        if available > 2 {
            // read checksum
            var s : String = String(self[nextread])
            s.append(self[nextread + 1])
            let cs = Int(s, radix: 16)
        
            if cs != checksum {
                print ("checksum error: " + String(cs ?? 0) + " != " + String(checksum) + " (" + s + ")")
            }
            nextread += 2
            
            // read \n\r
            if self[nextread] != "\r" || self[nextread + 1] != "\n" {
                print("invalid token at EOL " + String(self[nextread]))
                nextread += 2
                hl.lineType = .lineTypeInvalid
                return hl
            }
            nextread += 2
        }
                
        switch linetypechar {
            case "U":
                hl.lineType = .lineTypeRegistration
            case "A":
                hl.lineType = .lineTypeAlert
            case "F":
                hl.lineType = .lineTypeFuelFlow
            case "T":
                hl.lineType = .lineTypeTimestamp
            case "C":
                hl.lineType = .lineTypeConfig
            case "D":
                hl.lineType = .lineTypeFlight
            case "L":
                hl.lineType = .lineTypeLastLine
            default:
                hl.lineType = .lineTypeInvalid
        }
        
        if hl.lineType == .lineTypeInvalid {
            print ("invalid line type: %c\n", linetypechar)
        }
        print ("return new line, type: " + String(linetypechar))
        return hl
    }
    
    
    mutating func parseHeaders () -> EdmFileData {
        var edmfile =  EdmFileData()
        var hl = EdmHeaderLine()

        while hl.lineType != .lineTypeLastLine {
            hl = parseHeaderLine()
            switch hl.lineType {
                case .lineTypeRegistration:
                    edmfile.registration = edmfile.initRegistration(hl.contents) ?? ""
                case .lineTypeAlert:
                    edmfile.alarms = EdmAlarmLimits(hl.contents)
                case .lineTypeFuelFlow:
                    edmfile.ff = EdmFuelFlow(hl.contents)
                case .lineTypeTimestamp:
                    edmfile.date = edmfile.initDate(hl.contents)
                case .lineTypeConfig:
                    edmfile.config = EdmConfig(hl.contents)
                case .lineTypeFlight:
                    edmfile.flightInfos.append(EdmFlightData(hl.contents))
                case .lineTypeLastLine:
                    break
                default:
                    hl.lineType = .lineTypeLastLine
                    break
            }
        }
        return edmfile
    }
}


struct EdmHeaderLine {
    
    static let MAX_LEN = 256
    enum EdmLineType {
        case lineTypeInvalid
        case lineTypeRegistration
        case lineTypeAlert
        case lineTypeFuelFlow
        case lineTypeTimestamp
        case lineTypeConfig
        case lineTypeFlight
        case lineTypeLastLine
    }
    
    var lineType : EdmLineType = .lineTypeInvalid
    var contents : [String] = []
    var registration : String = ""
    var checkSum : Int
    
    init() {
        lineType = .lineTypeInvalid
        contents = []
        checkSum = 0
    }
    
}
