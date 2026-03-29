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
        let symbolName = importedSymbolName(for: symbol)
        guard let libraryOrdinal = importedLibraryOrdinal(for: symbolName, in: machO) else {
            return nil
        }

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
    static func importedSymbolName(for symbol: String) -> String {
        "_" + symbol
    }

    @usableFromInline
    static func importedLibraryOrdinal(
        for symbolName: String,
        in machO: MachOImage
    ) -> Int? {
        if let symbol = machO.bindingSymbols.first(where: {
            $0.symbolName == symbolName
        }) {
            return symbol.libraryOrdinal
        }
        if let symbol = machO.lazyBindingSymbols.first(where: {
            $0.symbolName == symbolName
        }) {
            return symbol.libraryOrdinal
        }
        if let symbol = machO.weakBindingSymbols.first(where: {
            $0.symbolName == symbolName
        }) {
            return symbol.libraryOrdinal
        }
        if let dyldChainedFixups = machO.dyldChainedFixups,
           let `import` = dyldChainedFixups.imports.first(where: {
               dyldChainedFixups.symbolName(for: $0.info.nameOffset) == symbolName
           }) {
            return `import`.info.libraryOrdinal
        }
        return nil
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
