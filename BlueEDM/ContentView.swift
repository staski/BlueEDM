//
//  ContentView.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 27.09.21.
//
import Foundation
import Combine
import SwiftUI
import UIKit
import EdmParser

extension View {
    func onLoad(perform action: (() -> Void)? = nil) -> some View {
        modifier(ViewDidLoadModifier(perform: action))
    }
}
struct UpperRightCornerText : View {
    var myText : Text
    @EnvironmentObject var edm : EDMBluetoothManager
    

    var body : some View {
        VStack
        {
            HStack
            {
                Spacer()
                myText.foregroundColor(Color.red).padding(10)
            }
            Spacer()
        }.border(Color.red, width: 2)
    }
}

struct ContentView: View {
    @EnvironmentObject var edm : EDMBluetoothManager
    
    var body : some View {
        ZStack
        {
            TabView {
                MainView().tabItem { Label("Home", systemImage: "house.fill") }
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
                FileListView().tabItem { Label("Files", systemImage: "doc.fill")}
            }
            if edm.isRawMode == true {
                UpperRightCornerText(myText: Text("Raw Mode"))
            }
        }
    }
}

struct FileListView : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var body: some View {
        NavigationView {
            List(edm.edmFiles) { file in
                NavigationLink(file.fileURL.lastPathComponent, destination: FileView(filename: file.fileURL))
            }.navigationTitle("EDM Files")
        }
    }
}

struct FileView : View {
    @State private var shareItem = false
    
    var filename : URL
    
    var text : String {
        var edmFileParser = EdmFileParser()
        var myText : String = ""

        guard let data = FileManager.default.contents(atPath: filename.path) else {
            return " -- invalid data --- "
        }
        
        edmFileParser.data = data
        // the parsed header file
        if edmFileParser.edmFileData.edmFileHeader == nil {
            if edmFileParser.available > 2000 {

                guard let header = edmFileParser.parseFileHeaders() else {
                    if !edmFileParser.invalid {
                        myText.append("received invalid data\n")
                    }
                    edmFileParser.invalid = true
                    return " -- invalid data --- "
                }
                edmFileParser.edmFileData.edmFileHeader = header
                myText.append(header.stringValue(includeFlights: false))
            }
        }
        
        guard let header = edmFileParser.edmFileData.edmFileHeader else {
            return " --- invalid --- "
        }
                
        for i in 0..<header.flightInfos.count
        {
            if edmFileParser.invalid == true {
                return " --- invalid --- "
            }
            
            let id = header.flightInfos[i].id
            guard let flightheader = edmFileParser.parseFlightHeaderAndSkip(for: id) else {
                return " --- invalid --- "
            }
            myText.append(flightheader.stringValue())
            myText.append("\n")
        }

        if edmFileParser.complete && edmFileParser.available > 0 {
            print("Data complete: " + String(edmFileParser.available) + " Bytes excess\n")
        }

        return myText
    }
    
    var body: some View {
            VStack
            {
                ScrollView {
                    Text(text).id(10)
                }.navigationBarItems(trailing: Button(action: { shareItem.toggle()})
                    {
                        Image(systemName: "square.and.arrow.up").imageScale(.large)
                    }.sheet(isPresented: $shareItem, content: {
                        ActivityViewController(url: filename)
                    })).navigationBarTitle(filename.lastPathComponent).navigationBarTitleDisplayMode(.inline)
            }
    }
}

struct MainView : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var body: some View {
            VStack(alignment: .center)
            {
                Spacer()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(edm.headerDataText).id(10)
                    }.onChange(of: edm.headerDataText) { target in
                        proxy.scrollTo(10, anchor: .bottom)
                    }
                }
                Spacer()
                RecordingView().disabled(!edm.deviceConnected)
                InfoView()
            }
    }
}

struct InfoView : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var dtext : String {
        return edm.deviceConnected ? String("Connected: " + edm.deviceName) : String("Not connected")
    }
    
    var rtext : String {
        return edm.receivedData.count != 0 ? String(format: "(%d bytes received)", edm.receivedData.count) : String("--")
    }
    
    var c1 : Color {
        return edm.deviceConnected ? Color.green : Color.orange
    }
    
    var body : some View {
        ZStack(alignment: .center, content: {
            HStack(alignment: .center, spacing: 10, content: {
                Circle().fill(c1).frame(width: 10.0, height: 10.0, alignment: .center).padding()
                Spacer()
            })
            VStack (alignment: .center, spacing: 10, content: {
                Text(dtext)
                Text(rtext)
            })
        })
    }
}

struct RecordingView : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var labelText : String {
        edm.deviceConnected ? (edm.isCapturing ? String("Stop Capturing") : String("Start Capturing")) : ""
    }
    
    var value : Double {
        if edm.isCapturing == false {
            return 0.0
        }
        if let h = edm.edmFileParser.edmFileData.edmFileHeader {
            let d = Double(edm.receivedData.count) / Double(h.totalLen)
            return d < 1.0 ? d : 1.0
        }
        else {
            return 0.0
        }
    }
    
    var body : some View {
        GroupBox {
            VStack {
            ZStack {
                HStack {
                    Text(labelText)
                    Spacer()
                }
                HStack(alignment: .center, spacing: 10){
                    Spacer()
                    Button(action: {
                        if self.edm.isCapturing == false {
                            self.edm.startCapturing()
                            edm.headerDataText.append("\n -- start capture -- \n")
                        }
                        else {
                            self.edm.stopCapturing()
                            let realDate = Date()
                            let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            
                            if edm.isRawMode == true {
                                let realName = "raw_edm_data_" + realDate.toString(dateFormat: "YYYYMMdd_HHmm") + ".jpi"
                                do {
                                    try edm.receivedData.write(to: documentPath.appendingPathComponent(realName))
                                } catch {
                                    trc(level: .error, string: "error while trying to write raw file \(error)" )
                                }
                                edm.isRawMode = false
                            }
                            /*
                             we save a hidden file with the download dateandtime in its name as found in the jpi file.
                             This is datetime is immutable and used to identify duplicates. On the other hand this datetime is
                             relative to to the time set on the EDM device, which might be wrong. Therefore we store the actual
                             data file with the "real" datetime in its name. The difference between the datetime in the name and the
                             datetime in the datefile itself can later be used to correct the flight dates (which are also relative
                             to the - potentially wrong - time setting of the EDM device
                             */
                            else if let fh = edm.edmFileParser.edmFileData.edmFileHeader {
                                let helperDate = fh.date!
                                
                                let helperName = "." + String(fh.registration) + "_" + helperDate.toString(dateFormat: "YYYYMMdd_HHmm") + "_hlp.jpi"
                                let realName = String(fh.registration) + "_" + realDate.toString(dateFormat: "YYYYMMdd_HHmm") + ".jpi"
                                
                                let edmHelperName = documentPath.appendingPathComponent(helperName)
                                let edmRealName = documentPath.appendingPathComponent(realName)
                                do {
                                    if !FileManager.default.fileExists(atPath: edmHelperName.path) {
                                        try edm.receivedData.write(to: edmRealName)
                                        try Data().write(to: edmHelperName)
                                        edm.headerDataText.append("written: " + realName)
                                        print ("written: " + realName)
                                    } else {
                                        edm.headerDataText.append("file already exists: " + helperName)
                                        print("file already exists: " + helperName)
                                    }
                                } catch {
                                    print ("error while trying to write \(error)")
                                }
                            } else {
                                if edm.receivedData.count != 0 {
                                    edm.headerDataText.append("invalid data - not saved\n")
                                    print ("invalid data - not saved")
                                }
                            }
                            edm.headerDataText.append("\n -- stop capture -- \n")
                            edm.fetchEdmFiles()
                        }
                    }) {
                        let i1 = Image(systemName: "pause.circle")
                        let i2 = Image(systemName: "record.circle")
                        
                        let fgcolor = edm.deviceConnected ? Color.red : Color.secondary
                        let i = edm.isCapturing ? i1 : i2
                        if #available(iOS 15.0, *) {
                            i.resizable().frame(width: 50, height: 50).symbolRenderingMode(.hierarchical).foregroundStyle(fgcolor)
                        } else {
                            i.resizable().frame(width: 50, height: 50).foregroundColor(fgcolor)
                        }
                    }
                    Spacer()
                }
            }
            }
            ProgressView(value: value)
        }
    }
}

struct ViewDidLoadModifier: ViewModifier {

    @State private var didLoad = false
    private let action: (() -> Void)?

    init(perform action: (() -> Void)? = nil) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content.onAppear {
            if didLoad == false {
                didLoad = true
                action?()
            }
        }
    }
}

var pipe = Pipe()

struct SettingsView : View {
    @EnvironmentObject var edm : EDMBluetoothManager
    @State private var myText: String = ""
    @State private var traceOn = false
    @State private var btleOn = true

    var toggleTitel : String {
        if edm.deviceConnected {
            return edm.deviceName
        } else {
            return "no device connected"
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Available BLE RS232 Devices")) {
                    HStack(){
                        Text(toggleTitel)
                        Spacer()
                        Button(action: {
                            guard let peripheral = edm.peripheral else {
                                return
                            }
                            edm.centralManager.cancelPeripheralConnection(peripheral)
                            edm.centralManager.scanForPeripherals(withServices: nil, options: nil)
                        }, label: {
                            HStack() {
                                Text("Rescan")
                                Image(systemName: "arrow.triangle.2.circlepath").imageScale(.medium)
                            }
                        })
                    }
                    if edm.deviceConnected == true {
                        VStack(alignment: .leading) {
                            Text("RSSI: " + String(edm.deviceRSSI) + " dB")
                        }
                    }                }
                /*
                Section(header: Text("Device Trace")){
                    Toggle("Activate Trace", isOn: $traceOn).onChange(of: traceOn){ _traceon in
                        self.redirectStdout()
                    }
                    TextEditor(text: $myText)
                }
                 */
                Section(header: Text("Raw Mode")){
                        Toggle("Enable Raw Mode", isOn: $edm.isRawMode).onChange(of: edm.isRawMode){ _rawmodeeon in
                    }
                }

            }
        }
    }
    
    
    func redirectStdout(){
        dup2(pipe.fileHandleForWriting.fileDescriptor,
              STDOUT_FILENO)
          // listening on the readabilityHandler
          pipe.fileHandleForReading.readabilityHandler = {
           handle in
          let data = handle.availableData
          let str = String(data: data, encoding: .ascii) ?? "<Non-ascii data of size\(data.count)>\n"
          DispatchQueue.main.async {
              myText += str
          }
        }
    }
}


struct ActivityViewController : UIViewControllerRepresentable {

    var url : URL

    @EnvironmentObject var edm : EDMBluetoothManager

    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil)
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


