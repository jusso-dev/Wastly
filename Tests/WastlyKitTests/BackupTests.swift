import Foundation
import Testing
@testable import WastlyKit

struct BackupTests {
    @Test func passwordRoundTrip() throws {
        let payload = BackupPayload(
            children: [BackupChild(id: UUID(), firstName: "Sam", dateOfBirth: Date(timeIntervalSince1970: 1_200_000_000))],
            logs: [],
            customFoods: [],
            energyUnit: .kilojoules
        )
        let envelope = try BackupCrypto.seal(payload: payload, password: "correct-horse")
        let opened = try BackupCrypto.open(envelope, password: "correct-horse")
        #expect(opened.children.first?.firstName == "Sam")
    }

    @Test func wrongPasswordFailsClosed() throws {
        let payload = BackupPayload(children: [], logs: [], customFoods: [], energyUnit: .kilojoules)
        let envelope = try BackupCrypto.seal(payload: payload, password: "right")
        #expect(throws: BackupError.wrongPassword) {
            _ = try BackupCrypto.open(envelope, password: "wrong")
        }
    }
}
