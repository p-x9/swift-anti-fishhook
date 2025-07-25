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
            let libraryName = machO.dependencies[libraryOrdinal - 1].dylib
                .name
                .machOName
            targetMachO = MachOImage(name: libraryName)
        }

        guard let targetMachO else { return nil }

        return _findExportedSymbol(symbol, in: targetMachO)
    }

    @usableFromInline
    static func _findExportedSymbol(_ symbol: String, in machO: MachOImage) -> UnsafeRawPointer? {
        guard let exportsTrie = machO.exportTrie,
              let exportedSymbol = exportsTrie.search(by: "_" + symbol) else {
            for reexport in machO.reexportDylibs {
                if let symbol = _findExportedSymbol(symbol, in: reexport) {
                    return symbol
                }
            }
            return nil
        }

        if exportedSymbol.flags.kind == .absolute,
           let offset = exportedSymbol.offset {
            return .init(bitPattern: offset)
        }

        if let resolver = exportedSymbol.resolver(for: machO) {
            return .init(bitPattern: resolver())
        }

        guard let offset = exportedSymbol.offset else { return nil }
        return machO.ptr.advanced(by: offset)
    }
}

extension MachOImage {
    var reexportDylibs: AnySequence<MachOImage> {
        let reexports = loadCommands.infos(of: LoadCommand.reexportDylib)
        return .init(
            reexports
                .lazy
                .map { $0.dylib(cmdsStart: cmdsStartPtr) }
                .map(\.name.machOName)
                .compactMap { MachOImage(name: $0) }
        )
    }
}

extension String {
    fileprivate var machOName: String {
        components(separatedBy: "/")
            .last!
            .components(separatedBy: ".")
            .first!
    }
}
