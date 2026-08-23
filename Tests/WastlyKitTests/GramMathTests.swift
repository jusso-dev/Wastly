import Testing
@testable import WastlyKit

struct GramMathTests {
    @Test func leftoverFromOffered() {
        #expect(GramMath.leftoverGrams(offered: 40, eaten: 30, wasted: 0) == 10)
    }

    @Test func wastedEnteredDirectly() {
        #expect(GramMath.leftoverGrams(offered: nil, eaten: 30, wasted: 10) == 10)
    }

    @Test func splitDoesNotGoNegative() {
        let split = GramMath.split(offered: 20, eaten: 50)
        #expect(split.eaten == 20)
        #expect(split.wasted == 0)
    }
}
