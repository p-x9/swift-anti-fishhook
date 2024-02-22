import XCTest
@testable import AntiFishHook
import MachOKit
import FishHook

final class AntiFishHookTests: XCTestCase {
    func test() {
        let item = StructItem()

        guard let machO = MachOImage(name: "AntiFishHookTests") else { return }
        guard let to = machO.symbol(
            named: "$s17AntiFishHookTests10StructItemV11replacementSSyF"
        ) else {
            return
        }

        /* Origianl */
        XCTAssertEqual(item.target(), "target")
        XCTAssertEqual(item.replacement(), "replacement")

        let targetSymbolName = "$s17AntiFishHookTests10StructItemV6targetSSyF"
        let rebindings: [Rebinding] = [
            .init(
                name: targetSymbolName,
                replacement: .init(mutating: machO.ptr.advanced(by: to.offset)),
                replaced: nil
            )
        ]

        /* Fish Hook */
        FishHook.rebind_symbols_image(
            machO: machO,
            rebindings: rebindings
        )

        XCTAssertEqual(item.target(), "replacement")
        XCTAssertEqual(item.replacement(), "replacement")

        /* Deny Fish Hook */
        AntiFishHook.denyFishHook(targetSymbolName, at: machO)

        XCTAssertEqual(item.target(), "target")
        XCTAssertEqual(item.replacement(), "replacement")
    }
}
