//
//  EmojiUtilities.swift
//  Remotion
//
//  Created by Dan Wood on 1/15/22.
//  Copyright © 2022 GroupUp Inc. All rights reserved.
//

import Foundation

protocol EmojiListProtocol {
    static var sharedInstance: any EmojiListProtocol { get }

    var allEmojiGroups: [EmojiGroup] { get }
}

// MARK: - Common Structs & Enums

/// Five skin tones supported by Emoji. Values are internal codes used to modify the base emoji string
enum SkinTone: UInt32, CaseIterable {
    case light = 0x1F3FB
    case mediumLight = 0x1F3FC
    case medium = 0x1F3FD
    case mediumDark = 0x1F3FE
    case dark = 0x1F3FF
}

/// Emoji grouped by category
struct EmojiGroup {
    let groupName: String
    var emojis: [EmojiInfo]
    var supportsSkinTones: Bool
}

/// Emoji we are keeping in memory; a subset of EmojiFullInfo
struct EmojiInfo {
    let string: String // The emoji itself
    let toneSupport: ToneSupport // Whether it can do skin tones
    let toneBaseString: String? // if supports skin tones, this may be our basis rather than the main emoji
}

/// How many tones an emoji supports
enum ToneSupport: Int, CaseIterable {
    case none, one, two
}

extension EmojiListProtocol {
    // MARK: - Toned to base lookup

    /// Brute force searches for base emoji from a toned emoji by looking for probable matches from the first character and then applying that
    /// tone until a match is found. Not called often so it's OK that it's inefficient!
    func findBaseEmoji(for tonedEmoji: String) -> String? {
        let foundSkinTones: [SkinTone] = tonedEmoji.foundSkinTones
        guard foundSkinTones.count > 0, // no skin tone? It's the original emoji
              let firstScalarValue: UInt32 = tonedEmoji.unicodeScalars.first?.value else { return tonedEmoji }

        if let candidateMatches: [EmojiInfo] = tonedEmojiIndex[firstScalarValue] {
            let result: String? = candidateMatches.first(where: { $0.applyingGivenTones(foundSkinTones) == tonedEmoji })?.string
            if result == nil {
                // Empirically there are some toned families where the first character doesn't match so try converting
                let keyOverrideLookup: [UInt32: [UInt32]] = [0x1F469: [0x1F46B, 0x1F46D],
                                                             0x1F468: [0x1F46C],
                                                             0x1F9D1: [0x1F48F, 0x1F491],
                                                             0x1FAF1: [0x1F91D]]
                if let overriddenKeys: [UInt32] = keyOverrideLookup[firstScalarValue] {
                    for overriddenKey: UInt32 in overriddenKeys {
                        // Try again
                        if let candidateMatches: [EmojiInfo] = tonedEmojiIndex[overriddenKey] {
                            let matched: String? = candidateMatches.first(where: { $0.applyingGivenTones(foundSkinTones) == tonedEmoji })?.string
                            if matched != nil {
                                return matched
                            }
                        }
                    }
                }
            } else {
                return result
            }
        }
        return nil // not found
    }

    /// Brute force searches for EmojiInfo record from a (toned or untoned) emoji by looking for probable matches from the first character
    func findEmojiInfo(for emoji: String) -> EmojiInfo? {
        let emojiToSearchFor: String
        let groupsToSearch: [EmojiGroup]
        if emoji.foundSkinTones.count > 0 {
            groupsToSearch = allEmojiGroups.filter { $0.supportsSkinTones }
            emojiToSearchFor = findBaseEmoji(for: emoji) ?? emoji
        } else {
            groupsToSearch = allEmojiGroups
            emojiToSearchFor = emoji
        }
        for group in groupsToSearch {
            if let foundEmojiInfo: EmojiInfo = group.emojis.first(where: { $0.string == emojiToSearchFor }) {
                return foundEmojiInfo
            }
        }
        return nil // not found
    }

    /// on-demand index, a dictionary with the key of the first UInt32 code point, the value an array of all characters that match.
    /// This reduces the number of combinations that we have to brute-force check!
    private var tonedEmojiIndex: [UInt32: [EmojiInfo]] {
        var result: [UInt32: [EmojiInfo]] = [:]
        let groupsWithSkinTones: [EmojiGroup] = allEmojiGroups.filter { $0.supportsSkinTones }
        groupsWithSkinTones.forEach {
            let groupResult
                = $0.emojis.reduce(into: [UInt32: [EmojiInfo]]()) { // $0 = partialResult, $1 = emoji
                    guard $1.toneSupport != .none else { return } // no need if it's not toned
                    if let firstScalarValue: UInt32 = $1.string.unicodeScalars.first?.value {
                        if let existingValues: [EmojiInfo] = $0[firstScalarValue] {
                            $0[firstScalarValue] = existingValues + [$1]
                        } else {
                            $0[firstScalarValue] = [$1]
                        }
                    }
                }
            result.merge(groupResult, uniquingKeysWith: { current, _ in current })
        }
        return result
    }
}

// MARK: - Loading

extension EmojiGroup {
    static func loadEmojiGroupsFrom(data emojiData: Data) -> [EmojiGroup] {
        guard let dataString: String = String(data: emojiData, encoding: .utf8)
        else {
            fatalError("Error decoding emoji Categories file")
        }
        var groups: [EmojiGroup] = []
        var groupName: String?
        var groupHasSkinTones: Bool = false
        var groupEmojis: [EmojiInfo] = []

        func addGroupedEmojis() {
            if let groupName = groupName, !groupName.isEmpty {
                let newGroup: EmojiGroup = EmojiGroup(groupName: groupName, emojis: groupEmojis, supportsSkinTones: groupHasSkinTones)
                groups.append(newGroup)
            }
        }
        func clearCurrentGroup() {
            groupName = nil
            groupHasSkinTones = false
            groupEmojis = []
        }

        let emojiVersionSupportedInThisOSVersion: Double = {
            let version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
            switch (version.majorVersion, version.minorVersion, version.patchVersion) {
            case (10, 14, _): return 11.0
            case (10, 15, 0): return 12.0
            case (10, 15, _): return 12.1 // Catalina 10.15.1 and up do Emoji 12.1
            case (10, _, _): return 0 // Other older 10.x operating systems, just assume it's too early when a version # is required
            case (11, 0 ... 2, _): return 13.0
            case (11, _, _), (12, 0 ... 2, _): return 13.1 // newer Big Sur, older Monterey has Emoji 13.1
            case (12, _, _), (13, 0 ... 2, _): return 14.0 // Emoji 14.0 in Monterey 12.3+ and early versions of Ventura
            case (13, _, _): return 15.0 // Emoji 15.0 in Ventura 12.3+

            default: return 15.0 // the Emoji version we reasonably expect to be in the future OS version not listed here
            }
        }()

        // Our emoji list indicates the version# each one was introduced starting with version 12.0. Earlier versions are not specified.
        func isSupported(version: Double?) -> Bool {
            guard let version = version else { return true } // if version is unspecified, assume compatible with ALL
            return emojiVersionSupportedInThisOSVersion >= version
        }

        /// Returns EmojiInfo if it's supported in running OS. Also adjusts in case skin tones aren't supported in running OS.
        func parseEmoji(line: String) -> EmojiInfo? {
            let s: String // The emoji itself
            let toneSupport: ToneSupport // Whether it can do skin tones
            let toneBaseString: String? // if supports 2 skin tones, use this basis rather than the main emoji
            let version: Double? // Version the emoji first appears in (starting with 12.0) or nil for lower versions
            let versionForTones: Double? // If a higher version is needed to show skin tones

            let fields: [Substring] = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > 0 else { return nil }
            s = String(fields[0])

            if fields.count > 1 {
                switch fields[1] {
                case "1":
                    toneBaseString = nil
                    toneSupport = .one
                case "":
                    toneBaseString = nil
                    toneSupport = .none
                default:
                    toneBaseString = String(fields[1])
                    toneSupport = .two
                }
            } else {
                toneSupport = .none
                toneBaseString = nil
            }
            if fields.count > 2, let number = Double(fields[2]) {
                version = number
            } else {
                version = nil
            }
            if fields.count > 3, let number = Double(fields[3]) {
                versionForTones = number
            } else {
                versionForTones = nil
            }

            guard isSupported(version: version) else { return nil }
            let useTones: Bool = isSupported(version: versionForTones)
            return EmojiInfo(string: s,
                             toneSupport: useTones ? toneSupport : .none,
                             toneBaseString: useTones ? toneBaseString : nil)
        }

        let lines: [Substring] = dataString.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            if line.isEmpty {
                addGroupedEmojis() // save away any group we are done parsing
                clearCurrentGroup() // get ready for next group
            } else if groupName == nil {
                let groupFields: [Substring] = line.split(separator: ",")
                if groupFields.count > 0 {
                    groupName = String(groupFields[0])
                }
                if groupFields.count > 1 {
                    groupHasSkinTones = !groupFields[1].isEmpty
                }
            } else {
                if let emojiInfo: EmojiInfo = parseEmoji(line: String(line)) {
                    groupEmojis.append(emojiInfo)
                }
            }
        }
        addGroupedEmojis() // save away last group
        return groups
    }
}

// MARK: - Utility methods for manipulating emoji strings

extension String {
    /// Add Variation Selector 0xFE0F to make a non-emoji into an emoji when applicable
    var addedVariationSelector: String {
        var scalars = [UnicodeScalar]()

        for scalar in unicodeScalars {
            scalars.append(scalar)
        }
        let variationCodepoint: UInt32 = 0xFE0F
        if let variation = Unicode.Scalar(variationCodepoint) {
            scalars.append(variation)
        }
        return scalars.string
    }

    /// For an emoji that supports a single skin tone, converts the "base" (toneless) emoji to the given skin tone.
    func addingOneSkinTone(_ tone: SkinTone) -> String {
        var wasToneInserted = false
        guard let toneScalar = Unicode.Scalar(tone.rawValue) else { return self }

        var scalars = [UnicodeScalar]()
        // Either replace first found Fully Qualified 0xFE0F, or add to the end or before the first ZWJ, 0x200D.

        for scalar in unicodeScalars {
            if !wasToneInserted {
                switch scalar.value {
                case 0xFE0F:
                    scalars.append(toneScalar) // tone scalar goes in place of the FE0F.
                    wasToneInserted = true
                case 0x200D:
                    scalars.append(toneScalar) // Insert the tone selector
                    scalars.append(scalar) // and then the ZWJ afterwards.
                    wasToneInserted = true
                default:
                    scalars.append(scalar)
                }
            } else { // already handled tone, just append the other selectors it finds.
                scalars.append(scalar)
            }
        }

        if !wasToneInserted {
            scalars.append(toneScalar) // Append at the end if needed.
        }
        return scalars.string
    }

    /// For an emoji that supports two skin tones. It converts the two-tone emoji that is that starting point into using the desired tones.
    func replacingSkinTones(_ tone1: SkinTone, _ tone2: SkinTone) -> String {
        // Replace the first tone scalar with tone1 and second tone scalar with tone2
        guard let tone1Scalar = Unicode.Scalar(tone1.rawValue),
              let tone2Scalar = Unicode.Scalar(tone2.rawValue),
              let first: UInt32 = SkinTone.allCases.first?.rawValue,
              let last: UInt32 = SkinTone.allCases.last?.rawValue else { return self }

        var scalars = [UnicodeScalar]()
        var hasAppendedTone1: Bool = false

        for scalar in unicodeScalars {
            if first ... last ~= scalar.value {
                scalars.append(!hasAppendedTone1 ? tone1Scalar : tone2Scalar)
                hasAppendedTone1 = true
            } else {
                scalars.append(scalar)
            }
        }
        return scalars.string
    }

    fileprivate var foundSkinTones: [SkinTone] {
        guard let first: UInt32 = SkinTone.allCases.first?.rawValue,
              let last: UInt32 = SkinTone.allCases.last?.rawValue else { return [] }
        var result: [SkinTone] = []
        let toneRange: ClosedRange<UInt32> = first ... last
        for scalar in unicodeScalars {
            if toneRange.contains(scalar.value) {
                if let skinTone = SkinTone(rawValue: scalar.value) {
                    result.append(skinTone)
                }
            }
        }
        return result
    }
}

private extension Sequence where Element == UnicodeScalar {
    var string: String { .init(String.UnicodeScalarView(self)) }
}

private extension EmojiInfo {
    func applyingGivenTones(_ skinTones: [SkinTone]) -> String {
        switch toneSupport {
        case .none:
            return string
        case .one:
            guard skinTones.count == 1,
                  let tone: SkinTone = skinTones.first else { return string }
            return string.addingOneSkinTone(tone)
        case .two:
            guard skinTones.count == 2,
                  let twoSkinTonesTemplate: String = toneBaseString,
                  let tone1: SkinTone = skinTones.first,
                  let tone2: SkinTone = skinTones.last
            else { return string }
            return twoSkinTonesTemplate.replacingSkinTones(tone1, tone2)
        }
    }
}
