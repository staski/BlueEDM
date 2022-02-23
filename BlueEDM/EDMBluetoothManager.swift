//
//  EDMBluetoothManager.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 05.10.21.
//

import Foundation
import Combine
import CoreBluetooth
import EdmParser

struct DataTransferService {
    static let lintechServiceUUID = CBUUID(string: "F18D63AE-CADC-11E3-AACB-1A514932AC01")
    static let lintechCharacteristicValueUUID = CBUUID(string: "F18D68AE-CADC-11E3-AACB-1A514932AC01")
    static let lintechCharacteristicCmdValueUUID = CBUUID(string: "F18D67AE-CADC-11E3-AACB-1A514932AC01")

    static let taskitServiceUUID = CBUUID(string: "912FFFF0-3D4B-11E3-A760-0002A5D5C51B")
    static let taskitCharacteristicValueUUID = CBUUID(string: "912FFFF1-3D4B-11E3-A760-0002A5D5C51B")
    static let taskitCharacteristicCmdValueUUID = CBUUID(string: "912FFFF2-3D4B-11E3-A760-0002A5D5C51B")
    
    static let dsdhm18ServiceUUID = CBUUID(string: "FFE0")
    static let dsdhm18CharacteristicValueUUID = CBUUID(string: "FFE1")
    static let dsdhm18CharacteristicCmdValueUUID = CBUUID(string: "FFE2")
}

enum BlueEdmDeviceType {
    case BlueEdmDeviceNone
    case BlueEdmDeviceLintech
    case BlueEdmDeviceTaskit
    case BlueEdmDeviceDsdhm18
}

extension Data {
    func readUInt() -> UInt? {
        guard self.count > 3 else {
            return nil
        }
        let a : UInt = UInt(self[0]) << 24 +  UInt(self[1]) << 16 + UInt(self[2]) << 8 + UInt(self[3])
        return a
    }
    
    func stringValue() -> String {
        var s : String = ""
        for i in 0..<self.count {
            s.append(Character(Unicode.Scalar(self[i])))
        }
        return s
    }
}

class EDMBluetoothManager : NSObject, ObservableObject{
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
    
    var edmFileParser : EdmFileParser = EdmFileParser()
    // index into the array of all flights indicating the next not yet parsed one
    var nextIndex : Int = 0
    
    private var cmdMode = false
    private var cmdCharacteristic : CBCharacteristic?
    private var valCharacteristic : CBCharacteristic?
    
    var deviceType : BlueEdmDeviceType = .BlueEdmDeviceNone
    private var cmdCount = 0 // the number of unresponded commands
    
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
            central.scanForPeripherals(withServices: nil /*[DataTransferService.taskitServiceUUID]*/, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        else {
            print("Bluetooth disconnected")
            if central.isScanning {
                print("stop scanning")
                central.stopScan()
            }
        }
        
    }
    
    func isPeripheralTaskit(_ advertisementData: [String : Any]) -> Bool {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else {
            print("isPeripheralTaskit: no service keys advertised by device " + (name ?? "unnamed"))
            return false
        }
        
        if uuids.contains(DataTransferService.taskitServiceUUID){
            print("isPeripheralTaskit: found task it device " + (name ?? "unnamed"))
            return true
        }
        return false
    }

    func isPeripheralLintech(_ advertisementData: [String : Any]) -> Bool {
        
        let manufacturerLinTech = 0x4401
        let deviceLinTechBTLE = 0x02ff
     
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let a = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            print("isPeripheralLintech: no manufacturer data available, ignore device " + (name ?? "unnamed") + "\n")
            return false
        }

        guard let num = a.readUInt() else {
            print("isPeripheralLintech: found non LinTech BTLE device " + (name ?? "unnamed") + "with manufacture Data:  " + a.description + "\n")
            print(advertisementData)
            return false
        }

        let device = num & 0xFFFF
        let manufacturer = (num & 0xFFFF0000) >> 16

        if manufacturer != manufacturerLinTech || device != deviceLinTechBTLE {
            print("isPeripheralLintech: found non LinTech BTLE device " + (name ?? "unnamed") + ", " + a.description)
            print(String(format: "num: 0x%04X manufacturer: 0x%04X, device: 0x%04X\n", num, manufacturer, device))
            return false
        }
        
        return true
    }

    func isPeripheralDsdhm18(_ advertisementData: [String : Any]) -> Bool {
        
        let manufacturerDsdhm = 0x484d
        // let deviceDsdhm18BLE = 0x6098
     
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let a = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            print("isPeripheralDsdhm18: no manufacturer data available, ignore device " + (name ?? "unnamed") + "\n")
            return false
        }

        guard let num = a.readUInt() else {
            print("isPeripheralDsdhm18: found non HM18 BLE device " + (name ?? "unnamed") + "with manufacture Data:  " + a.description + "\n")
            print(advertisementData)
            return false
        }

        let device = num & 0xFFFF
        let manufacturer = (num & 0xFFFF0000) >> 16

        if manufacturer != manufacturerDsdhm {
            print("isPeripheralDsdhm18: found non DSD HM BLE device " + (name ?? "unnamed") + ", " + a.description)
            print(String(format: "num: 0x%04X manufacturer: 0x%04X, device: 0x%04X\n", num, manufacturer, device))
            return false
        }

        print("isPeripheralDsdhm18: found DSD HM BLE device " + (name ?? "unnamed") + ", " + a.description)
        print(String(format: "num: 0x%04X manufacturer: 0x%04X, device: 0x%04X\n", num, manufacturer, device))

        return true
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        if (isPeripheralTaskit(advertisementData)){
            deviceType = BlueEdmDeviceType.BlueEdmDeviceTaskit
        } else if (isPeripheralLintech(advertisementData)){
            deviceType = BlueEdmDeviceType.BlueEdmDeviceTaskit
        } else if (isPeripheralDsdhm18(advertisementData)){
            deviceType = BlueEdmDeviceType.BlueEdmDeviceDsdhm18
        }
        
        if deviceType == .BlueEdmDeviceNone {
            printAdvertisementData(advertisementData: advertisementData)
            return
        }
        
        self.peripheral = peripheral

        if let pname = peripheral.name {
            self.centralManager.stopScan()
            
            print ("found BLE RS232 Device " + (peripheral.name ?? "--"))
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
        deviceType = .BlueEdmDeviceNone
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for pservice in peripheral.services! {
            print(pservice)
            if pservice.uuid == DataTransferService.lintechServiceUUID {
                peripheral.discoverCharacteristics([DataTransferService.lintechCharacteristicValueUUID, DataTransferService.lintechCharacteristicCmdValueUUID], for: pservice)
            }
            if pservice.uuid == DataTransferService.taskitServiceUUID {
                peripheral.discoverCharacteristics([DataTransferService.taskitCharacteristicValueUUID, DataTransferService.taskitCharacteristicCmdValueUUID], for: pservice)
            }
            if pservice.uuid == DataTransferService.dsdhm18ServiceUUID {
                peripheral.discoverCharacteristics([DataTransferService.dsdhm18CharacteristicValueUUID, DataTransferService.dsdhm18CharacteristicCmdValueUUID], for: pservice)
            }
        }
   }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        print("characteristics for service--" + service.description + "--\n")
        for pcharacteristic in service.characteristics! {
            if pcharacteristic.uuid == DataTransferService.lintechCharacteristicValueUUID {
                print("register for transfer service value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                valCharacteristic = pcharacteristic
            }

            if pcharacteristic.uuid == DataTransferService.taskitCharacteristicValueUUID {
                print("register for transfer service value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                valCharacteristic = pcharacteristic
            }

            if pcharacteristic.uuid == DataTransferService.dsdhm18CharacteristicValueUUID {
                print("register for transfer service value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                valCharacteristic = pcharacteristic
                // the HM devices accept commands over the "regular" value characteristic
                cmdCharacteristic = pcharacteristic
                initDevice()
            }
            
            if pcharacteristic.uuid == DataTransferService.lintechCharacteristicCmdValueUUID {
                print("register for transfer service cmd value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                cmdCharacteristic = pcharacteristic
                initDevice()
            }
            
            if pcharacteristic.uuid == DataTransferService.taskitCharacteristicCmdValueUUID {
                print("register for transfer service cmd value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                cmdCharacteristic = pcharacteristic
                initDevice()
            }

            if pcharacteristic.uuid == DataTransferService.dsdhm18CharacteristicCmdValueUUID {
                print("register for transfer service command value")
                peripheral.setNotifyValue(true, for: pcharacteristic)
                valCharacteristic = pcharacteristic
                cmdCharacteristic = pcharacteristic
                initDevice()
            }

            print(pcharacteristic.uuid.uuidString)
            printProperties(pcharacteristic.properties)
            print(pcharacteristic.description)
        }
    }
    
    func initDevice() {
        switch deviceType {
            case .BlueEdmDeviceLintech:
            sendCmd("UART=5,1,0")
            sendCmd("INDI=0")
            sendCmd("TXPO=4")
        case .BlueEdmDeviceTaskit:
            print("initDevice: no init actions defined for TaskIt device")
            //readCmd()
            //sendCmd("3")
        case .BlueEdmDeviceDsdhm18:
            sendCmd("AT+BAUD?")
            sendCmd("AT+POWE?")
        default:
            print ("initDevice: no device available, ignore")
        }
    }

    // send a command to the peripheral
    func sendCmd (_ cmd: String, characteristic : CBCharacteristic? = nil)  {
    
        var data = Data()
        if deviceType == .BlueEdmDeviceTaskit {
            let v = cmd.utf8.first!
            data = Data(repeating: v, count: 1)
        } else {
            data = Data(cmd.utf8)
        }
        
        guard let c = cmdCharacteristic else {
            print("no characteristic for commands available\n")
            return
        }
        
        guard let peripheral = self.peripheral else {
            print ("no peripheral\n")
            return
        }

        print ("sendCmd: " + cmd)
        cmdCount += 1
        peripheral.writeValue(data, for: c, type: .withResponse )
    }
    
    // read the return value of the sendCmd, triggered by writeValueFor
    func readCmdReturn (_ data : Data){
        if deviceType == .BlueEdmDeviceDsdhm18 {
            let s : String = data.stringValue()
            print ("BLE device returned \(s) from write")
        }
        
        if deviceType != .BlueEdmDeviceTaskit {
            return
        }

        if data.count == 1 {
            let b = UInt8(data[0])
            print ("readCmdReturn: current data cmd value is \(b)")
            if (b != 3){
                print("readCmdReturn: set it to 3 (19200,8,N,1)")
                sendCmd("3")
            }
        }
        else {
            print(data.description)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("Write error " + error.localizedDescription + "occured for characteristic" + characteristic.uuid.uuidString)
            if cmdCount > 0 {
                cmdCount -= 1
            }
            return
        }
        
        if cmdCount > 0 {
            cmdCount -= 1
        } else {
            print("didWriteValueFor: \(characteristic) no write open")
            return
        }
        
        if characteristic == cmdCharacteristic || characteristic == valCharacteristic {
            peripheral.setNotifyValue(true, for: characteristic)

            guard let d = characteristic.value else {
                print(characteristic)
                printProperties(characteristic.properties)
                print ("return from write ok without data")
                return
            }
        
            print ("didWriteValueFor: returned " + d.stringValue() + ";")
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("Read error " + error.localizedDescription + "occured for characteristic" + characteristic.uuid.uuidString)
        }
        
        if cmdCount > 0 && characteristic == cmdCharacteristic {
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
                nextIndex = 0
                headerDataText.append(header.stringValue(includeFlights: false))
            }
        }
        
        guard let header = edmFileParser.edmFileData.edmFileHeader else {
            return
        }
        
        for i in nextIndex..<header.flightInfos.count
        {
            
            let id = header.flightInfos[i].id
            
            let size = header.flightInfos[i].sizeBytes
            
            if edmFileParser.available < size {
                return
            }
            
            guard let flightheader = edmFileParser.parseFlightHeaderAndSkip(for: id) else {
                return
            }
            nextIndex += 1
            headerDataText.append(flightheader.stringValue())
            
        }
        
        
        trc(level: .all, string: "nextIndex: \(nextIndex), count: \(header.flightInfos.count), available: \(edmFileParser.available)")
        if (nextIndex >= header.flightInfos.count) && (edmFileParser.available > 0) {
            trc(level: .info,string: "Data complete: " + String(edmFileParser.available) + " Bytes excess\n")
        }
    }
    
    func printAdvertisementData (advertisementData : [String : Any]) {
        for a in advertisementData {
            switch a.key {
            case CBAdvertisementDataIsConnectable:
                let v = a.value as? NSNumber
                print (a.key + ": " + (v ?? NSNumber(0)).stringValue)
                break
            case CBAdvertisementDataLocalNameKey:
                let v = a.value as? String
                print (a.key + ": " + (v ?? " not present"))
                break
            case CBAdvertisementDataManufacturerDataKey:
                let v = a.value as? NSData
                print (a.key + ": " + (v ?? NSData()).description)
                break
            case CBAdvertisementDataOverflowServiceUUIDsKey:
                let v = a.value as? [CBUUID]
                print (a.key + ": ")
                if v != nil {
                    for i in v! {
                        print (i.uuidString)
                    }
                }
                break
            case CBAdvertisementDataServiceDataKey:
                let v = a.value as? [CBUUID : NSData]
                print (a.key + ": ")
                if v != nil {
                    for i in v! {
                        print (i.key.uuidString + ": " + i.value.description)
                    }
                }
                break
            case CBAdvertisementDataServiceUUIDsKey:
                let v = a.value as? [CBUUID]
                print (a.key + ": ")
                if v != nil {
                    for i in v! {
                        print (i.uuidString)
                    }
                }
                break
            case CBAdvertisementDataSolicitedServiceUUIDsKey:
                let v = a.value as? [CBUUID]
                print (a.key + ": ")
                if v != nil {
                    for i in v! {
                        print (i.uuidString)
                    }
                }
                break
            case CBAdvertisementDataTxPowerLevelKey:
                let v = a.value as? NSNumber
                print (a.key + ": " + (v ?? NSNumber(0)).stringValue)
                break
            default:
                break
            }
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

