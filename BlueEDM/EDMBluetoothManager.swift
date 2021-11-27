//
//  EDMBluetoothManager.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 05.10.21.
//

import Foundation
import Combine
import CoreBluetooth

struct DataTransferService {
    static let serviceUUID = CBUUID(string: "F18D63AE-CADC-11E3-AACB-1A514932AC01")
    static let characteristicValueUUID = CBUUID(string: "F18D68AE-CADC-11E3-AACB-1A514932AC01")
    static let characteristicCmdValueUUID = CBUUID(string: "F18D67AE-CADC-11E3-AACB-1A514932AC01")
}

extension Data {
    func readUInt() -> UInt? {
        guard self.count > 3 else {
            return nil
        }
        let a : UInt = UInt(self[0]) << 24 +  UInt(self[1]) << 16 + UInt(self[2]) << 8 + UInt(self[3])
        return a
    }
}

class EDMBluetoothManager : NSObject, ObservableObject{
    
    static let manufacturerLinTech = 0x4401
    static let deviceLinTechBTLE = 0x02ff

    let willChange = PassthroughSubject<Void, Never>()
    
    var centralManager = CBCentralManager()
    var peripheral : CBPeripheral?
    
    @Published var deviceFound = false
    @Published var deviceName: String = ""
    @Published var deviceRSSI = ""
    @Published var deviceConnected = false
    @Published var isCapturing = false
    @Published var shareItem = false
    @Published var headerDataText = ""
    
    @Published var receivedData : Data = Data()
    
    // the saved files 1:1
    var edmFiles = [EdmFile]()
    
    // the parsed header file
    var edmFileParser : EdmFileParser = EdmFileParser()
    
    private var cmdMode = false
    private var cmdCharacteristic : CBCharacteristic?
    private var valCharacteristic : CBCharacteristic?
    
    override init() {
        super.init()
        self.centralManager.delegate = self
        self.fetchEdmFiles()
    }
    
    func startCapturing () {
        receivedData = Data()
        edmFileParser = EdmFileParser()
        isCapturing = true
    }
    
    func stopCapturing (){
        isCapturing = false
    }
    
    func fetchEdmFiles() {
        edmFiles.removeAll()
        
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directoryContents = try! fileManager.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        
        for f in directoryContents {
            let myid = getCreationDate(for: f)
            let edmFile = EdmFile(fileURL: f, createdAt: myid)
            edmFiles.append(edmFile)
        }
        edmFiles.sort(by: { $0.createdAt.compare($1.createdAt) == .orderedDescending})
        willChange.send()
    }
}

extension EDMBluetoothManager : CBCentralManagerDelegate, CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == CBManagerState.poweredOn {
            print("Bluetooth powered on")
            central.scanForPeripherals(withServices: nil, options: nil)
        }
        else {
            print("Bluetooth disconnected")
            if central.isScanning {
                print("stop scanning")
                central.stopScan()
            }
        }
        
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        guard let a = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            print("no manufacturer data available, ignore device: " + (peripheral.name ?? "nil") + "\n")
            return
        }

        guard let num = a.readUInt() else {
            print("found non LinTech BTLE device: " + (peripheral.name ?? "") + "with manufacture Data:  " + a.description + "\n")
            print(advertisementData)
            return
        }

        let device = num & 0xFFFF
        let manufacturer = (num & 0xFFFF0000) >> 16

        if manufacturer != EDMBluetoothManager.manufacturerLinTech || device != EDMBluetoothManager.deviceLinTechBTLE {
            print("found non LinTech BTLE device:  " + (peripheral.name ?? "") + ", " + a.description)
            print(String(format: "num: 0x%04X manufacturer: 0x%04X, device: 0x%04X\n", num, manufacturer, device))
            return
        }
        
        self.peripheral = peripheral

        if let pname = peripheral.name {
            self.centralManager.stopScan()
            
            print ("found BTLE RS232 Device " + (peripheral.name ?? "--"))
            self.deviceFound = true
            self.peripheral!.delegate = self
            self.deviceName = pname
            self.deviceRSSI = String(Int(truncating: RSSI))
            willChange.send()

            self.centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        deviceConnected = true
        peripheral.discoverServices(nil)
    }
        
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        self.stopCapturing()
        print (deviceName + " disconnected ")
        deviceFound = false
        deviceConnected = false
        deviceName = "No Device"
        deviceRSSI = ""
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for pservice in peripheral.services! {
            print(pservice)
            if pservice.uuid == DataTransferService.serviceUUID {
                peripheral.discoverCharacteristics([DataTransferService.characteristicValueUUID, DataTransferService.characteristicCmdValueUUID], for: pservice)
            }
        }
   }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        print("characteristics for service--" + service.description + "--\n")
        for pcharacteristic in service.characteristics! {
            if pcharacteristic.uuid == DataTransferService.characteristicValueUUID {
                print("register for transfer service value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                valCharacteristic = pcharacteristic
            }

            if pcharacteristic.uuid == DataTransferService.characteristicCmdValueUUID {
                print("register for transfer service cmd value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                cmdCharacteristic = pcharacteristic
                softReset()
            }
            print(pcharacteristic.uuid.uuidString)
            printProperties(pcharacteristic.properties)
            print(pcharacteristic.description)
        }
    }
    
    func softReset() {
        sendCmd("UART=5,1,0")
        sendCmd("INDI=0")
        sendCmd("TXPO=4")
        //sendCmd("COMA=0")
        //sendCmd("COMMAND:AT+INFO=1\r")
    }
    
    func sendCmd (_ cmd: String, characteristic : CBCharacteristic? = nil)  {
        let data = Data(cmd.utf8)
        
        guard let c = cmdCharacteristic else {
            print("no characteristic for commands available\n")
            return
        }
        
        guard let peripheral = self.peripheral else {
            print ("no peripheral\n")
            return
        }

        print ("send cmd: " + cmd)
        peripheral.writeValue(data, for: c, type: .withResponse )
    }

    func sendCmdVal (_ cmd: String, characteristic : CBCharacteristic? = nil)  {
        let data = Data(cmd.utf8)
        
        guard let c = valCharacteristic else {
            print("no characteristic for commands available\n")
            return
        }

        guard let peripheral = self.peripheral else {
            print ("no peripheral\n")
            return
        }

        peripheral.writeValue(data, for: c, type: .withResponse )
    }

    func readCmdReturn (_ data : Data){
        print(data.description)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("Write error " + error.localizedDescription + "occured for characteristic" + characteristic.uuid.uuidString)
        }
        
        if characteristic == cmdCharacteristic || characteristic == valCharacteristic {
            peripheral.setNotifyValue(true, for: characteristic)

            guard let d = characteristic.value else {
                print(characteristic)
                printProperties(characteristic.properties)
                print ("return from write ok without data")
                return
            }
            
            readCmdReturn(d)

            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("Read error " + error.localizedDescription + "occured for characteristic" + characteristic.uuid.uuidString)
        }
        
        //print("received update for characteristic " + characteristic.description + ", value: " + (characteristic.value?.description ?? ""))
        if characteristic == cmdCharacteristic {
            guard let d = characteristic.value else {
                print ("no return data for cmd received")
                return
            }
            
            readCmdReturn(d)
            return
        }
        
        guard let data = characteristic.value else {
            return
        }
        
        guard isCapturing == true else {
            return
        }
        
        receivedData.append(data)
        edmFileParser.data.append(data)

        if edmFileParser.edmFileData.edmFileHeader == nil {
            if edmFileParser.available > 2000 {

                guard let header = edmFileParser.parseFileHeaders() else {
                    if !edmFileParser.invalid {
                        headerDataText.append("received invalid data\n")
                    }
                    edmFileParser.invalid = true
                    return
                }
                edmFileParser.edmFileData.edmFileHeader = header
                headerDataText.append(header.stringValue())
            }
        }
        
        guard let header = edmFileParser.edmFileData.edmFileHeader else {
            return
        }
                
        while edmFileParser.complete == false && edmFileParser.available >= header.flightInfos[edmFileParser.nextFlightIndex!].sizeBytes {
            guard let flightheader = edmFileParser.parseFlightHeaderAndSkip() else {
                return
            }
            
            headerDataText.append(flightheader.stringValue())
        }
        
        if edmFileParser.complete && edmFileParser.available > 0 {
            print("Data complete: " + String(edmFileParser.available) + " Bytes excess\n")
        }
    }
}

func printProperties (_ properties : CBCharacteristicProperties){
    print("  ==PROPERTIES==  ")
    
    if properties.contains(CBCharacteristicProperties.authenticatedSignedWrites){
        print("authenticatedSignedWrites")
    }
    if properties.contains(CBCharacteristicProperties.broadcast){
        print("broadcast")
    }
    if properties.contains(CBCharacteristicProperties.extendedProperties){
        print("authenticatedSignedWrites")
    }
    if properties.contains(CBCharacteristicProperties.authenticatedSignedWrites){
        print("extendedProperties")
    }
    if properties.contains(CBCharacteristicProperties.indicate){
        print("indicate")
    }
    if properties.contains(CBCharacteristicProperties.indicateEncryptionRequired){
        print("indicateEncryptionRequired")
    }
    if properties.contains(CBCharacteristicProperties.notify){
        print("notify")
    }
    if properties.contains(CBCharacteristicProperties.notifyEncryptionRequired){
        print("notifyEncryptionRequired")
    }
    if properties.contains(CBCharacteristicProperties.read){
        print("read")
    }
    if properties.contains(CBCharacteristicProperties.write){
        print("write")
    }
    if properties.contains(CBCharacteristicProperties.writeWithoutResponse){
        print("writeWithoutResponse")
    }
}

func getCreationDate(for file: URL) -> Date {
    if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) as [FileAttributeKey: Any],
        let creationDate = attributes[FileAttributeKey.creationDate] as? Date {
        return creationDate
    } else {
        return Date()
    }
}

