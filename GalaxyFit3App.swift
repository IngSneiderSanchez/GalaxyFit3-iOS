
import SwiftUI
import CoreBluetooth

@main
struct GalaxyFit3App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class Fit3Manager: NSObject, ObservableObject,
                         CBCentralManagerDelegate,
                         CBPeripheralDelegate {
    @Published var status = "Buscando pulsera..."
    @Published var heartRate: Int?
    private var central: CBCentralManager!
    private var watch: CBPeripheral?

    private let heartService =
        CBUUID(string: "180D")
    private let heartCharacteristic =
        CBUUID(string: "2A37")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            status = "Bluetooth activo. Buscando..."
            central.scanForPeripherals(withServices: nil)
        } else {
            status = "Activa el Bluetooth del iPhone"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard watch == nil else { return }
        watch = peripheral
        central.stopScan()
        peripheral.delegate = self
        status = "Conectando a \(peripheral.name ?? "dispositivo")..."
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        status = "Conectado. Consultando servicios..."
        peripheral.discoverServices([heartService])
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard error == nil else {
            status = "Error leyendo servicios"
            return
        }
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics(
                [heartCharacteristic], for: $0)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else { return }
        service.characteristics?.forEach {
            if $0.uuid == heartCharacteristic {
                peripheral.setNotifyValue(true, for: $0)
                status = "Escuchando frecuencia cardíaca"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil,
              let data = characteristic.value,
              data.count >= 2 else { return }

        let bytes = [UInt8](data)
        let bpm: Int
        if bytes[0] & 1 == 1 {
            guard bytes.count >= 3 else { return }
            bpm = Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            bpm = Int(bytes[1])
        }
        heartRate = bpm
    }
}

struct ContentView: View {
    @StateObject private var fit3 = Fit3Manager()

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Galaxy Fit3")
                .font(.largeTitle.bold())

            Text(fit3.status)
                .multilineTextAlignment(.center)

            Text(fit3.heartRate.map { "\($0) BPM" } ?? "-- BPM")
                .font(.system(size: 42, weight: .semibold))

            Text("Conexión Bluetooth experimental")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
