import XCTest
@testable import AntiFishHook
import MachOKit
import FishHook

final class AntiFishHookTests: XCTestCase {
    func test() {
        let item = StructItem()

        guard let machO = MachOImage(name: "AntiFishHookTests") else { return }
        guard let to = machO.symbol(
            named: "_$s17AntiFishHookTests10StructItemV11replacementSSyF"
        ) else {
            XCTFail("Could not find symbol")
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

extension AntiFishHookTests {
    func testDlsymHook() {
        guard let machO = MachOImage(name: "AntiFishHookTests") else { return }
        guard let to = machO.symbol(
            named: "_$s17AntiFishHookTests6dlsym2ySvSgAC_SPys4Int8VGSgtF"
        ) else {
            XCTFail("Could not find symbol")
            return
        }

        let targetSymbolName = "dlsym"
        let rebindings: [Rebinding] = [
            .init(
                name: targetSymbolName,
                replacement: .init(mutating: machO.ptr.advanced(by: to.offset)),
                replaced: nil
            )
        ]

        /* Fish Hook */
        FishHook.rebind_symbols(
            rebindings: rebindings
        )

        let handle = UnsafeMutableRawPointer(mutating: machO.ptr) // dlopen("path", RTLD_NOW)
        print(dlsym(handle, "$s17AntiFishHookTests10StructItemV11replacementSSyF").debugDescription)

        AntiFishHook.denyFishHook(targetSymbolName, at: machO)

        print(dlsym(handle, "$s17AntiFishHookTests10StructItemV11replacementSSyF").debugDescription)
    }
}

public func dlsym2(_ __handle: UnsafeMutableRawPointer!, _ __symbol: UnsafePointer<CChar>!) -> UnsafeMutableRawPointer! {
    print("hooked", __handle.debugDescription, __symbol.debugDescription)
    return .init(bitPattern: 0)
}

extension AntiFishHookTests {
    func testFindExportedSymbolResolvesReexportsWhenAvailable() throws {
        for image in MachOImage.images {
            guard let exportTrie = image.exportTrie else { continue }

            for exportedSymbol in exportTrie.exportedSymbols
            where exportedSymbol.flags.contains(.reexport) {
                XCTAssertNotNil(
                    AntiFishHook._findExportedSymbol(
                        named: exportedSymbol.name,
                        in: image
                    )
                )
                return
            }
        }

        throw XCTSkip("No re-exported symbols were available in loaded images")
    }
}
