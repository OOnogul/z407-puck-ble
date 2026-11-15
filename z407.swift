// z407: control a Logitech Z407 speaker over Bluetooth LE.
// No arguments: opens a menu. With a command name: sends that one command and exits.
// Protocol from freundTech's Protocol.md (facts only, no code copied).

import CoreBluetooth
import Foundation

let serviceUUID = CBUUID(string: "0000fdc2-0000-1000-8000-00805f9b34fb")
let commandUUID = CBUUID(string: "c2e758b9-0e78-41e0-b0cb-98a593193fc5")
let responseUUID = CBUUID(string: "b84ac9c6-29c5-46d4-bba1-9d534784330f")

let commands: [String: UInt16] = [
    "bass-up": 0x8000,
    "bass-down": 0x8001,
    "volume-up": 0x8002,
    "volume-down": 0x8003,
    "play-pause": 0x8004,
    "next": 0x8005,
    "prev": 0x8006,
    "input-bt": 0x8101,
    "input-aux": 0x8102,
    "input-usb": 0x8103,
    "pair": 0x8200,
    "factory-reset": 0x8300,
    "chime-1": 0x8501,
    "chime-2": 0x8502,
    "chime-3": 0x8503,
    "unknown-1": 0x8500,
]

// Menu entries. factory-reset and unknown-1 are CLI-only so they can't be picked by accident.
let menu: [(label: String, name: String)] = [
    ("Volume up", "volume-up"),
    ("Volume down", "volume-down"),
    ("Bass up", "bass-up"),
    ("Bass down", "bass-down"),
    ("Play/pause", "play-pause"),
    ("Next track", "next"),
    ("Previous track", "prev"),
    ("Input: Bluetooth", "input-bt"),
    ("Input: AUX", "input-aux"),
    ("Input: USB", "input-usb"),
    ("Pairing mode", "pair"),
    ("Chime 1", "chime-1"),
    ("Chime 2", "chime-2"),
    ("Chime 3", "chime-3"),
]

// Set Z407_DEBUG=1 to print each connection step to stderr.
let debugOn = ProcessInfo.processInfo.environment["Z407_DEBUG"] != nil
func debug(_ message: String) {
    if debugOn { FileHandle.standardError.write(Data(("debug: " + message + "\n").utf8)) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    print("usage: z407                      (no arguments opens the menu)")
    print("       z407 <command> [--timeout SECONDS] [--yes]")
    print("commands: " + commands.keys.sorted().joined(separator: ", "))
    print("factory-reset needs --yes")
    exit(2)
}

func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

// One session per command. A fresh object keeps late CoreBluetooth callbacks
// from an earlier command away from the current one.
final class Z407Session: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let code: UInt16
    let confirmHex: String
    var central: CBCentralManager?
    var peripheral: CBPeripheral?
    var commandChar: CBCharacteristic?
    let times: Int
    var sentCommand = false
    var sentCount = 0
    var confirmedCount = 0
    var sentAt = Date()
    var outcome: (ok: Bool, message: String)?

    init(code: UInt16, times: Int = 1) {
        self.code = code
        self.times = times
        self.confirmHex = String(format: "%04x", code + 0x4000)  // 0x80XX is confirmed by 0xC0XX
        super.init()
    }

    func summary() -> String {
        "sent 0x\(String(format: "%04x", code)) x\(times), confirmed \(confirmedCount) of \(times)"
    }

    func finish(_ ok: Bool, _ message: String) {
        if outcome == nil { outcome = (ok, message) }
    }

    // Blocks until the command is confirmed, fails, or times out.
    func run(timeout: Double) -> (ok: Bool, message: String) {
        central = CBCentralManager(delegate: self, queue: nil)
        let deadline = Date().addingTimeInterval(timeout)
        while outcome == nil {
            sendNext()
            if sentCount == times && Date().timeIntervalSince(sentAt) > 2 {
                // The speaker confirms most commands. Stop waiting 2 s after the last send.
                finish(true, summary())
            } else if Date() > deadline {
                finish(false, "Timed out. Is the speaker on and the original dial out of its battery bay?")
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if let c = central, let p = peripheral { c.cancelPeripheralConnection(p) }
        central?.stopScan()
        return outcome!
    }

    func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let c = commandChar else { return }
        p.writeValue(Data(bytes), for: c, type: .withoutResponse)
    }

    // Sends the next copy once the pause since the last one has passed.
    // Called from the run loop, so the pause is enforced in one place.
    func sendNext() {
        guard sentCommand, sentCount < times, let p = peripheral, let c = commandChar else { return }
        if sentCount > 0 && Date().timeIntervalSince(sentAt) < pressGap { return }
        guard p.canSendWriteWithoutResponse else { return }
        let data = Data([UInt8(code >> 8), UInt8(code & 0xFF)])
        p.writeValue(data, for: c, type: .withoutResponse)
        sentCount += 1
        sentAt = Date()
    }

    func sendCommand() {
        sentCommand = true
        sendNext()
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        case .poweredOff:
            finish(false, "Bluetooth is off.")
        case .unauthorized:
            finish(false, "Bluetooth access denied. Allow your terminal under System Settings > Privacy & Security > Bluetooth.")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        debug("discovered \(peripheral.name ?? "unnamed") rssi \(RSSI)")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        debug("connected")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(false, "Could not connect: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish(false, "Speaker disconnected before the command finished.")
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        debug("services: \(peripheral.services?.map { $0.uuid.uuidString } ?? []) error: \(String(describing: error))")
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            finish(false, "Z407 service not found.")
            return
        }
        peripheral.discoverCharacteristics([commandUUID, responseUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics,
              let command = chars.first(where: { $0.uuid == commandUUID }),
              let response = chars.first(where: { $0.uuid == responseUUID }) else {
            finish(false, "Z407 characteristics not found.")
            return
        }
        debug("characteristics found")
        commandChar = command
        peripheral.setNotifyValue(true, for: response)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            finish(false, "Could not subscribe: \(error.localizedDescription)")
            return
        }
        debug("notify state: \(characteristic.isNotifying)")
        // Handshake step 1. The speaker answers 0xd40501.
        write([0x84, 0x05])
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        debug("rx \(hex(value))")
        switch hex(value) {
        case "d40501":
            write([0x84, 0x00])  // handshake step 2
        case "d40001", "d40003":
            // Handshake done. The speaker may skip d40003, and the working
            // projects (androrama, freundTech) both treat d40001 as connected.
            if !sentCommand { sendCommand() }
        case confirmHex:
            confirmedCount += 1
            if confirmedCount == times { finish(true, summary()) }
        default:
            break
        }
    }

}

func runCommand(code: UInt16, times: Int = 1, timeout: Double) -> (ok: Bool, message: String) {
    Z407Session(code: code, times: times).run(timeout: timeout)
}

let maxTimes = 50

// Pause between repeated presses. Presses sent faster than this can be ignored.
// Z407_GAP=0.6 overrides it for testing.
let pressGap: TimeInterval = Double(ProcessInfo.processInfo.environment["Z407_GAP"] ?? "") ?? 0.3

func runMenu() {
    print("Logitech Z407 remote")
    print("Volume and bass change one step per press. The speaker does not report its level.")
    print("Type a number, or a number and a count, for example 4 4 (max \(maxTimes)).")
    while true {
        print()
        for (i, item) in menu.enumerated() {
            print("  \(i + 1)) \(item.label)")
        }
        print("  q) quit")
        print("> ", terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else {
            print()
            return  // Ctrl-D
        }
        if line == "q" || line == "quit" { return }

        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first, let n = Int(first), (1...menu.count).contains(n),
              let code = commands[menu[n - 1].name] else {
            print("Pick a number from the list, or q to quit.")
            continue
        }
        var times = 1
        if parts.count > 1 {
            guard parts.count == 2, let t = Int(parts[1]), (1...maxTimes).contains(t) else {
                print("The count must be 1 to \(maxTimes), for example: 4 4")
                continue
            }
            times = t
        }
        let result = runCommand(code: code, times: times, timeout: 30)
        print(result.ok ? result.message : "Error: \(result.message)")
    }
}

// MARK: entry point

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    runMenu()
    exit(0)
}

guard let name = args.first, let code = commands[name] else { usage() }

var timeout: Double = 30
var yes = false
var i = 1
while i < args.count {
    switch args[i] {
    case "--timeout":
        i += 1
        guard i < args.count, let value = Double(args[i]), value > 0 else { usage() }
        timeout = value
    case "--yes":
        yes = true
    default:
        usage()
    }
    i += 1
}

if name == "factory-reset" && !yes {
    fail("factory-reset wipes the speaker settings. Add --yes to confirm.")
}

let result = runCommand(code: code, timeout: timeout)
if result.ok {
    print(result.message)
    exit(0)
}
fail(result.message)
