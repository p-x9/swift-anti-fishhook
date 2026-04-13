import Foundation
import MachOKit
import FishHook

public enum AntiFishHook {
    @inlinable
    @inline(__always)
    static public func denyFishHook(_ symbol: String) {
        for image in MachOImage.images {
            denyFishHook(symbol, at: image)
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

        for targetMachO in targetMachOs(for: libraryOrdinal, in: machO) {
            if let symbolAddress = _findExportedSymbol(named: symbolName, in: targetMachO) {
                return symbolAddress
            }
        }
        return nil
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
    static func targetMachOs(
        for libraryOrdinal: Int,
        in machO: MachOImage
    ) -> [MachOImage] {
        if let bindSpecial = BindSpecial(rawValue: numericCast(libraryOrdinal)) {
            switch bindSpecial {
            case .dylib_self:
                return [machO]
            case .dylib_main_executable:
                return [MachOImage.currentExecutable]
            case .dylib_flat_lookup, .dylib_weak_lookup:
                return Array(MachOImage.images)
            }
        }

        let index = libraryOrdinal - 1
        guard machO.dependencies.indices.contains(index) else { return [] }

        let libraryName = machO.dependencies[index].dylib.name.machOName
        guard let targetMachO = MachOImage(name: libraryName) else { return [] }
        return [targetMachO]
    }

    @usableFromInline
    static func _findExportedSymbol(named symbolName: String, in machO: MachOImage) -> UnsafeRawPointer? {
        var visitedImages: Set<Int> = []
        return _findExportedSymbol(
            named: symbolName,
            in: machO,
            visitedImages: &visitedImages
        )
    }


    @usableFromInline
    static func _findExportedSymbol(
        named symbolName: String,
        in machO: MachOImage,
        visitedImages: inout Set<Int>
    ) -> UnsafeRawPointer? {
        let imageAddress = Int(bitPattern: machO.ptr)
        guard visitedImages.insert(imageAddress).inserted else { return nil }

        guard let exportsTrie = machO.exportTrie,
              let exportedSymbol = exportsTrie.search(by: symbolName) else {
            return _findExportedSymbolInReexports(
                named: symbolName,
                in: machO,
                visitedImages: &visitedImages
            )
        }

        if exportedSymbol.flags.contains(.reexport) {
            let reexportedSymbolName = exportedSymbol.importedName
                .flatMap { $0.isEmpty ? nil : $0 } ?? symbolName

            if let ordinal = exportedSymbol.ordinal {
                for targetMachO in targetMachOs(for: Int(ordinal), in: machO) {
                    if let symbolAddress = _findExportedSymbol(
                        named: reexportedSymbolName,
                        in: targetMachO,
                        visitedImages: &visitedImages
                    ) {
                        return symbolAddress
                    }
                }
            }

            return _findExportedSymbolInReexports(
                named: reexportedSymbolName,
                in: machO,
                visitedImages: &visitedImages
            )
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

    @usableFromInline
    static func _findExportedSymbolInReexports(
        named symbolName: String,
        in machO: MachOImage,
        visitedImages: inout Set<Int>
    ) -> UnsafeRawPointer? {
        for reexport in machO.reexportDylibs {
            if let symbolAddress = _findExportedSymbol(
                named: symbolName,
                in: reexport,
                visitedImages: &visitedImages
            ) {
                return symbolAddress
            }
        }
        return nil
    }
}

extension MachOImage {
    var reexportDylibs: AnySequence<MachOImage> {
        let reexports = loadCommands.infos(of: LoadCommand.reexportDylib)
            .map { $0.dylib(cmdsStart: cmdsStartPtr) }

        let newreexports = loadCommands.infos(of: LoadCommand.loadDylib)
            .compactMap { $0.dylibUseCommand(in: self) }
            .filter { $0.flags.contains(.reexport) }
            .map { $0.dylib(cmdsStart: cmdsStartPtr) }

        return .init(
            (reexports + newreexports)
                .lazy
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
