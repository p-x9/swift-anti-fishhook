import Foundation
import MachOKit
import FishHook

public enum AntiFishHook {
    @inlinable
    @inline(__always)
    static public func denyFishHook(_ symbol: String) {
        var symbolAddress: UnsafeRawPointer?
        for image in MachOImage.images {
            if symbolAddress == nil {
                symbolAddress = find(symbol, in: image)
            }
            if let symbolAddress {
                FishHook.rebind_symbols_image(
                    machO: image,
                    rebindings: [
                        .init(
                            name: symbol,
                            replacement: .init(mutating: symbolAddress),
                            replaced: nil
                        )
                    ]
                )
            }
        }
    }

    @inlinable
    @inline(__always)
    @discardableResult
    static public func denyFishHook(_ symbol: String, at image: MachOImage) -> Bool {
        guard let symbolAddress = find(symbol, in: image) else {
            return false
        }
        FishHook.rebind_symbols_image(
            machO: image,
            rebindings: [
                .init(
                    name: symbol,
                    replacement: .init(mutating: symbolAddress),
                    replaced: nil
                )
            ]
        )
        return true
    }
}

extension AntiFishHook {
    @usableFromInline
    static func find(_ symbol: String, in machO: MachOImage) -> UnsafeRawPointer? {
        var libraryOrdinal: Int?

        if let symbol = machO.bindingSymbols.first(where: {
            $0.symbolName == "_" + symbol
        }) { libraryOrdinal = symbol.libraryOrdinal }
        else if let symbol = machO.lazyBindingSymbols.first(where: {
            $0.symbolName == "_" + symbol
        }) { libraryOrdinal = symbol.libraryOrdinal }
        else if let symbol = machO.weakBindingSymbols.first(where: {
            $0.symbolName == "_" + symbol
        }) { libraryOrdinal = symbol.libraryOrdinal }

        else if let dyldChainedFixups = machO.dyldChainedFixups,
           let `import` = dyldChainedFixups.imports.first(where: {
               dyldChainedFixups.symbolName(for: $0.info.nameOffset) == "_" + symbol
           }) {
            libraryOrdinal = `import`.info.libraryOrdinal
        }

        guard let libraryOrdinal else { return nil }
        var targetMachO: MachOImage?

        if libraryOrdinal == 0 {
            targetMachO = machO
        } else {
            let libraryName = machO.dependencies[libraryOrdinal - 1].dylib.name
                .components(separatedBy: "/")
                .last!
                .components(separatedBy: ".")
                .first!
            targetMachO = MachOImage(name: libraryName)
        }

        guard let targetMachO else { return nil }

        return _findExportedSymbol(symbol, in: targetMachO)
    }

    @usableFromInline
    static func _findExportedSymbol(_ symbol: String, in machO: MachOImage) -> UnsafeRawPointer? {
        let exportedSymbols = machO.exportedSymbols
        guard let exportedSymbol = exportedSymbols.first(where: {
            $0.name == "_" + symbol
        }) else { return nil }
        return machO.ptr.advanced(by: exportedSymbol.offset)
    }
}
