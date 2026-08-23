import Testing
@testable import WastlyKit

struct BarcodeTests {
    @Test func stripsLeadingZeros() {
        #expect(Barcode.normalized("0009300652804562") == "9300652804562")
        #expect(Barcode.matches("0004011", "4011"))
    }

    @Test func unknownDoesNotMatch() {
        #expect(Barcode.matches("4011", "4131") == false)
        #expect(Barcode.normalized("0000").isEmpty)
    }

    @Test func preservesMeaningOfPaddedCode() {
        #expect(Barcode.matches("09300652804562", "9300652804562"))
    }
}
