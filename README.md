# swift-anti-fishhook

A Swift library to deactivate fishhook. (Anti-FishHook)

(Made with [MachOKit](https://github.com/p-x9/MachOKit))

<!-- # Badges -->

[![Github issues](https://img.shields.io/github/issues/p-x9/swift-anti-fishhook)](https://github.com/p-x9/swift-anti-fishhook/issues)
[![Github forks](https://img.shields.io/github/forks/p-x9/swift-anti-fishhook)](https://github.com/p-x9/swift-anti-fishhook/network/members)
[![Github stars](https://img.shields.io/github/stars/p-x9/swift-anti-fishhook)](https://github.com/p-x9/swift-anti-fishhook/stargazers)
[![Github top language](https://img.shields.io/github/languages/top/p-x9/swift-anti-fishhook)](https://github.com/p-x9/swift-anti-fishhook/)

## Usage

Specify the symbol name of the function for which you want to disable hooks by fishhook.

```swift
import AntiFishHook

AntiFishHook.denyFishHook("$s17AntiFishHookTests10StructItemV6targetSSyF")
```

## License

swift-anti-fishhook is released under the MIT License. See [LICENSE](./LICENSE)
