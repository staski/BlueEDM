//
//  EdmFileList.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 11.10.21.
//

import SwiftUI
import EdmParser

struct EdmFile : Identifiable {
    var id: Date { createdAt }
    
    let edmFileParser : EdmFileParser
    let fileURL: URL
    let createdAt: Date
}

extension EdmFlightHeader : Identifiable {
}

struct NavigationLazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

struct EdmFileListItem: View {
    let name : String
    let value : String
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
        }
    }
}


struct FileListView : View {
    @EnvironmentObject var edm : EDMBluetoothManager
    @State private var showSharing : Bool = false
    
    var body: some View {
        var shareUrl : URL? = nil
        
        NavigationView {
            if #available(iOS 15.0, *) {
                List {
                    ForEach (edm.edmFiles) { file in
                        NavigationLink{ NavigationLazyView(FileView(file.fileURL)) } label: {
                            Text(file.fileURL.lastPathComponent)
                        }.swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button{
                                shareUrl = file.fileURL
                                showSharing.toggle()
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up.fill")
                            }.tint(.blue)
                        }.swipeActions(allowsFullSwipe: false) {
                            Button(role: .destructive) {
                            edm.deleteFile(file.fileURL)
                            edm.fetchEdmFiles()
                        } label: {
                            Label("Delete \(file.fileURL.path)", systemImage: "trash.fill")
                            }
                        }.sheet(isPresented: $showSharing) {
                            if shareUrl != nil {
                                ActivityViewController(shareItem: EdmFileDetailsJSON(url: shareUrl!))
                            }
                        }
                    }
                }.navigationTitle("EDM Files")
            } else {
                // Fallback on earlier versions
                List(edm.edmFiles) { file in
                    NavigationLink(file.fileURL.lastPathComponent, destination: NavigationLazyView(FileView(file.fileURL)))
                }.navigationTitle("EDM Files")
            }
        }
    }
}

typealias EdmFilename = String

extension EdmFilename {
    func getDownloadDate() -> Date? {
        if #available(iOS 16.0, *) {
            let regex = /_(\d+_\d+).jpi/
            if let match = self.firstMatch(of: regex){
                let datestring = String(match.1)
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US")
                dateFormatter.dateFormat = "YYYYMMdd_HHmm"
                if let dt = dateFormatter.date(from: datestring){
                    return dt
                }
            }
        }
        return nil
    }
    
    func getShadowFilename() -> String? {
        if #available(iOS 16.0, *) {
            let regex = /(.*)_(\d+_\d+).jpi/
            if let match = self.firstMatch(of: regex){
                let first = String(match.1)
                let datestring = String(match.2)
                return "." + first + "_" + datestring + "_hlp.jpi"
            }
        }
        return nil
    }
}


struct EdmErrorView : View {
    var text : String
    var body: some View {
        VStack(alignment: .center){
            HStack(alignment: .center){
                Text(text).font(.system(size: 24, weight: .bold))
            }
        }
    }
}

struct FileView : View {
    @State private var shareItem = false
    
    var fileurl : URL
    
    var d : Data
    var p : EdmFileParser
    var h : EdmFileHeader?
    var fh : [EdmFlightHeader]
    var c : Int
    var filename : String
    var shadowname : String = "NONE"
    var savedatdate : Date?
    
    init (_ url: URL) {
        fileurl = url
        filename = fileurl.lastPathComponent
        savedatdate = self.filename.getDownloadDate()
        d = FileManager.default.contents(atPath: fileurl.path) ?? Data()
        p = EdmFileParser(data: d)
        h = p.parseFileHeaders()
        fh = [EdmFlightHeader]()
        c = h != nil ? h!.flightInfos.count : 0

        if h == nil {
            fh = [EdmFlightHeader]()
            return
        }

        p.edmFileData.edmFileHeader = h
        trc(level: .info, string: "Init FileView: \(h!.flightInfos.count)")

        for i in 0..<c
        {
            if p.invalid == true {
                fh = [EdmFlightHeader]()
                h = nil
                return
            }
            let id = h!.flightInfos[i].id
            trc(level: .error, string: "Init FileView: \(id)")

            if h!.flightInfos[i].sizeBytes == 0 {
                trc(level: .error, string: "FileView::init: flightId \(h!.flightInfos[i].id) has no content")
                continue
            }
            
            guard let flightheader = p.parseFlightHeaderAndSkip(for: id) else {
                fh = [EdmFlightHeader]()
                h = nil
                return
            }

            fh.append(flightheader)
        }
        
        let helperDate = h!.date!
        shadowname = "." + String(h!.registration) + "_" + helperDate.toString(dateFormat: "YYYYMMdd_HHmm") + "_hlp.jpi"
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tmpurl = documentPath.appendingPathComponent(shadowname)
        if !FileManager.default.fileExists(atPath: tmpurl.path) {
            shadowname = " NONE "
        }
    }

    var text : String {
        var myText : String = ""

        guard let header = h  else {
            return " -- invalid data --- "
        }

        myText.append(header.config.features.stringValue())
        myText.append(header.alarms.stringValue())
        myText.append(header.ff.stringValue())
        if p.complete && p.available > 0 {
            print("Data complete: " + String(p.available) + " Bytes excess\n")
        }

        return myText
    }
    
    @State private var topExpanded: Bool = false
    @State private var showSharing: Bool = false
    var body: some View {
            var shareUrl : URL? = nil
            var shareId : Int? = nil
            
            if h == nil {
                EdmErrorView(text: "INVALID JPI FILE")
            } else {
                VStack
                {
                    let registration = h!.registration
                    List {
                        Section(header: Text("File infos")){
                            EdmFileListItem(name: "Filename", value: self.filename)
                            EdmFileListItem(name: "Size", value: String(Int((h!.totalLen)/1024)) + " KB")
                            EdmFileListItem(name: "Download date", value: (h!.date?.toString() ?? ""))
                            if #available(iOS 16.0, *) {
                                EdmFileListItem(name: "Saved at", value: savedatdate?.toString() ?? "no shadow file available")
                            } else {
                                EdmFileListItem(name: "Saved at", value: savedatdate?.toString() ?? "available with iOS16 or higher")
                            }
                        }
                        Section(header: Text("Device infos"), footer:
                                    DisclosureGroup("Details", isExpanded: $topExpanded){ Text(text) })
                        {
                            EdmFileListItem(name: "Registration", value: registration)
                            EdmFileListItem(name: "Model", value: "EDM" + String( h!.config.modelNumber))
                            EdmFileListItem(name: "SW-Version", value: String(h!.config.version))
                        }
                        Section(header: Text(String(c) + " Flights")){
                            ForEach(fh) { flight in
                                if #available(iOS 15.0, *) {
                                    NavigationLink {
                                        NavigationLazyView(EdmFlightDetailView(data: d,id: Int(flight.id)))
                                    } label: {
                                        EdmFileListItem(name: "ID " + String(flight.id), value: flight.date?.toString() ?? "")
                                    }.swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button(action:  {
                                            shareUrl = fileurl
                                            shareId = Int(flight.id)
                                            showSharing.toggle()
                                        }){
                                            Label("Share", systemImage: "square.and.arrow.up.fill")
                                        }
                                    }.tint(.blue).sheet(isPresented: $showSharing) {
                                        if shareUrl != nil && shareId != nil {
                                            ActivityViewController(shareItem: EdmFlightDetailsJSON(url: shareUrl!, id: shareId!))
                                        }
                                    }
                                } else {
                                    NavigationLink {
                                        NavigationLazyView(EdmFlightDetailView(data: d,id: Int(flight.id)))
                                    } label: {
                                        EdmFileListItem(name: "ID " + String(flight.id), value: flight.date?.toString() ?? "")
                                    }
                                }
                            }
                        }
                    }.navigationBarItems(trailing: Button(action: { shareItem.toggle()}){
                            Image(systemName: "square.and.arrow.up").imageScale(.large)
                        }.sheet(isPresented: $shareItem, content: {
                            ActivityViewController(shareItem: fileurl)
                        })).navigationBarTitle("JPI File").navigationBarTitleDisplayMode(.inline)
                    }
            }
    }
}

