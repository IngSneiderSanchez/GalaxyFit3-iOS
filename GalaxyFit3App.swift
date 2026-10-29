
import SwiftUI
import CoreBluetooth
import Combine

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

    @Published var status = "Iniciando Bluetooth..."
    @Published var heartRate: Int?

    private var central: CBCentralManager!
    private var watch: CBPeripheral?

    private let heartService = CBUUID(string: "180D")
    private let heartCharacteristic = CBUUID(string: "2A37")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Buscando Galaxy Fit3..."
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .poweredOff:
            status = "Activa el Bluetooth del iPhone."
        case .unauthorized:
            status = "Permite el uso de Bluetooth."
        case .unsupported:
            status = "Bluetooth LE no compatible."
        default:
            status = "Esperando Bluetooth..."
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (
            peripheral.name ??
            advertisementData[CBAdvertisementDataLocalNameKey] as? String ??
            ""
        ).lowercased()

        guard name.contains("fit3"), watch == nil else {
            return
        }

        watch = peripheral
        central.stopScan()
        peripheral.delegate = self

        status = "Conectando a \(peripheral.name ?? "Galaxy Fit3")..."
        central.connect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        status = "Conectado. Buscando frecuencia cardíaca..."
        peripheral.discoverServices([heartService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        watch = nil
        status = "No se pudo conectar. Reinicia la búsqueda."
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        heartRate = nil
        watch = nil
        status = "Desconectado. Reinicia la búsqueda."
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil else {
            status = "Error al consultar servicios."
            return
        }

        guard let service = peripheral.services?.first(
            where: { $0.uuid == heartService }
        ) else {
            status = "No se encontró el servicio cardíaco."
            return
        }

        peripheral.discoverCharacteristics(
            [heartCharacteristic],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristic = service.characteristics?.first(
                where: { $0.uuid == heartCharacteristic }
              ) else {
            status = "No se encontró la lectura cardíaca."
            return
        }

        peripheral.setNotifyValue(true, for: characteristic)
        status = "Conectado. Esperando pulsaciones..."
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == heartCharacteristic,
              let data = characteristic.value,
              data.count >= 2 else {
            return
        }

        let bytes = [UInt8](data)
        let bpm: Int

        if bytes[0] & 1 == 1 {
            guard bytes.count >= 3 else { return }
            bpm = Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            bpm = Int(bytes[1])
        }

        heartRate = bpm
        status = "Frecuencia cardíaca recibida."
    }
}

struct ContentView: View {
    @StateObject private var fit3 = Fit3Manager()

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Galaxy Fit3")
                .font(.largeTitle.bold())

            Text(fit3.status)
                .multilineTextAlignment(.center)

            Text(
                fit3.heartRate.map { "\($0) BPM" } ?? "-- BPM"
            )
            .font(.system(size: 42, weight: .semibold))

            Text("Conexión Bluetooth experimental")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
