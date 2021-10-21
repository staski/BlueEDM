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


extension View {
    func onLoad(perform action: (() -> Void)? = nil) -> some View {
        modifier(ViewDidLoadModifier(perform: action))
    }

}

struct ContentView: View {
    
    var body : some View {
        TabView {
            MainView().tabItem { Label("Home", systemImage: "house.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

struct MainView : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var body: some View {
        NavigationView {
            VStack(alignment: .center)
            {
                //HeaderView().frame(height: 30)
                Spacer()
                EdmFileList()
                Spacer()
                RecordingView().disabled(!edm.deviceConnected)
                InfoView()
                Button(action: { edm.shareItem.toggle()}) {
                                    Text("Share Data")
                                    Image(systemName: "square.and.arrow.up")
                }.sheet(isPresented: $edm.shareItem, content: {
                    ActivityViewController()
                            })
            }.navigationBarTitle("EDM Bluetooth")
        }
    }
}

struct InfoView : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var dtext : String {
        return edm.deviceConnected ? String("Connected: " + edm.deviceName) : String("Not connected")
    }
    
    var rtext : String {
        return edm.receivedData.count != 0 ? String(format: "(%d bytes received)", edm.receivedData.count) : String("")
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

struct Info1View : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var text : String {
        var mytext : String = ""
        if (edm.deviceConnected){
            mytext = String(format: "%d bytes received", edm.receivedData.count)
            return mytext
        }
        else{
            return "Not connected"
        }
    }
    var body : some View {
            Text(text)
    }
}

extension Date
{
    func toString( dateFormat format  : String ) -> String
    {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        return dateFormatter.string(from: self)
    }

}
struct RecordingView : View {
    @EnvironmentObject var edm : EDMBluetoothManager

    var labelText : String {
        edm.isCapturing ? String("Stop Capturing") : String("Start Capturing")
    }
    var body : some View {
        GroupBox {
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
                        }
                        else {
                            let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let edmFilename = documentPath.appendingPathComponent("\(Date().toString(dateFormat: "dd-MM-YY_'at'_HH:mm:ss")).jpi")
                            print (edmFilename)
                            edm.stopCapturing()
                            if edm.receivedData.count != 0 {
                                do {
                                    try edm.receivedData.write(to: edmFilename)
                                } catch {
                                    print ("error while trying to write \(error)")
                                }
                            }
                            edm.fetchEdmFiles()
                        }
                    }) {
                        Image(systemName: edm.isCapturing ? "stop.circle" : "record.circle").resizable()
  //                          .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .clipped()
                            .foregroundColor(.red)
//                            .padding(.bottom, 10)
                    }
                    Spacer()
                }
            }
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

struct SettingsView : View {
    @EnvironmentObject var edm : EDMBluetoothManager
    @State private var myText: String = ""
    @State private var traceon = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Available BLE RS232 Devices")) {
                    if edm.deviceFound == true {
                        VStack {
                            Text("Name: " + edm.deviceName)
                            Text("RSSI: " + String(edm.deviceRSSI))
                        }
                    }
                }
                Section(header: Text("Device Trace")){
                    Toggle("Activate Trace", isOn: $traceon).onChange(of: traceon){ _traceon in
                        self.redirectStdout()
                    }
                    TextEditor(text: $myText)
                }
            }
        }.onLoad {
//            redirectStdout()
        }
    }
    
    var pipe = Pipe()
    
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

    @EnvironmentObject var edm : EDMBluetoothManager

    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        
        let controller = UIActivityViewController(
            activityItems: [edm.receivedData],
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


