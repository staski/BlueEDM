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

class EDMBluetoothManager : NSObject, ObservableObject{
    
    let willChange = PassthroughSubject<Void, Never>()
    
    private let centralManager = CBCentralManager()
    var peripheral : CBPeripheral!
    
    @Published var deviceFound = false
    @Published var deviceName: String = ""
    @Published var deviceRSSI = 0
    @Published var deviceConnected = false
    @Published var isCapturing = false
    @Published var shareItem = false
    
    private var receivedSize = 0
    @Published var receivedData : Data = Data()
    
    var edmFiles = [EdmFile]()
    
    override init() {
        super.init()
        self.centralManager.delegate = self
        self.fetchEdmFiles()
    }
    
    func startCapturing () {
        receivedSize = 0
        receivedData = Data()
        isCapturing = true
    }
    
    func stopCapturing (){
        isCapturing = false
    }
    
    func fetchEdmFiles() {
        edmFiles.removeAll()
        
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directoryContents = try! fileManager.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
        
        for f in directoryContents {
            let edmFile = EdmFile(fileURL: f, createdAt: getCreationDate(for: f))
            edmFiles.append(edmFile)
        }
        edmFiles.sort(by: { $0.createdAt.compare($1.createdAt) == .orderedDescending})
        willChange.send()
    }
}



extension EDMBluetoothManager : CBCentralManagerDelegate, CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == CBManagerState.poweredOn {
            print("BLE powered on")
            central.scanForPeripherals(withServices: nil, options: nil)
        }
        else {
            print("Something wrong with BLE")
        }
        
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral

        if let pname = peripheral.name {
            if pname == "DEEBU BLE" {
                self.centralManager.stopScan()
                
                print ("found BLE RS232 Device")
                self.deviceFound = true
                self.peripheral = peripheral
                self.peripheral.delegate = self
                self.deviceName = pname
                self.deviceRSSI = Int(truncating: RSSI)
                willChange.send()

                self.centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        deviceConnected = true
        peripheral.discoverServices(nil)
        print("")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        self.stopCapturing()
        deviceConnected = false
        deviceName = "No Device"
        deviceRSSI = 0
        print ("Device disconnected, start scanning ...")
        central.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for pservice in peripheral.services! {
            print(pservice)
            if pservice.uuid == DataTransferService.serviceUUID {
                peripheral.discoverCharacteristics([DataTransferService.characteristicValueUUID, DataTransferService.characteristicCmdValueUUID], for: pservice)
            }
        }
        print("")
   }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        for pcharacteristic in service.characteristics! {
            if pcharacteristic.uuid == DataTransferService.characteristicValueUUID {
                print("register for transfer service value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                peripheral.readValue(for: pcharacteristic)
            }
        }
        print ("\n")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        guard let data = characteristic.value else {
            return
        }
        
        var tmpstring = "capturing"
        
        //print (characteristic)
        if (isCapturing){
            receivedData.append(data)
        } else {
            tmpstring = "not " + tmpstring
        }
        
        receivedSize += data.count  
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

