//
//  GenerateEmojiLists.swift
//  GenerateEmoji
//
//  Created by Dan Wood on 2/2/22.
//

import Foundation
import EmojiUtilities

// MARK: - Support for saving/loading

/// For loading emojis before filtering them out
private struct EmojiFullGroup {
    let groupName: String
    var emojis: [EmojiFullInfo]
    var supportsSkinTones: Bool
}

/// Per-emoji info we read from disk, before filtering out the unsupported versions
/// Some fields are 'var' since they are modified as the data structures are built up. Plus, there are additional fields not written out.
private struct EmojiFullInfo {
    let string: String // The emoji itself
    var toneSupport: ToneSupport // Whether it can do skin tones
    var toneBaseString: String? // if supports 2 skin tones, use this basis rather than the main emoji
    let version: Double? // Version the emoji first appears in (starting with 12.0) or nil for lower versions.
    let versionForTones: Double? // If a higher version is needed to show skin tones
    
    // Working data; not written to JSON
    var unqualifieds: Set<String>      // Other unqualified encodings of emoji that might match
    let info: String
}

class EmojiParser: NSObject, XMLParserDelegate {
    
    static let latestKnownEmojiVersion: Double = 15.0  // corresponding to emoji-test.txt and en.xml data files, which may not be known in OS yet
    static let latestSupportedEmojiVersion: Double = 15.0   // and to the version supported in this operating system including AppleName.strings
    
    // MARK: - Additional Search Terms
    
    let additionalEnglishTerms: [String: [String]] = [
        "🕴": // Note: this is the code point from the en.xml file, not the fully-qualified one we end up using from emoji-test.txt
        ["ska", "ghost town", "walt jabsco", "magritte"],
        "🎃": ["pumpkin"],
        "⭕": ["remotion"],
        "🐶": ["pup", "puppy", "doge", "doggo"],

        // Some additional terms to compensate for Emojibase not yet having Emoji 15.0. These are some likely short terms in that style.
        "🩵": ["lightblue heart"],
        "🫷": ["lefthand"],
        "🫸": ["righthand"],
        "🐦‍⬛": ["blackbird"],
        "🫚": ["ginger"],
        "🫛": ["peapod"],
        "🪭": ["fan"],
        "🪮": ["hairpick"],
        "🛜": ["wifi"],

    ]
    
    // MARK: Data
    
    fileprivate static var emojiFullGroups: [EmojiFullGroup] = []
    var initialAnnotations: [String: [String]] = [:] // Annotations loaded from raw file; several keys are not fully-qualified versions of the emoji
    var annotations: [String: [String]] = [:]        // cleaned up
    var appleNames: [String: String]  = [:]
    var emojibases: [String: Set<String>]  = [:]

    // MARK: Parsing
    
    let desktopURL = URL(fileURLWithPath: NSString("~/Desktop").expandingTildeInPath)       // Working directory for input and output files
    
    func parseEverything() {
        loadFiles()
        crossReference()
        saveFiles()
        printReport()
    }
    
    // MARK: Loading
    
    func loadFiles() {
        let emojiTestURL = desktopURL.appendingPathComponent("emoji-test.txt")
        let cldrAnnotationsURL = desktopURL.appendingPathComponent("en.xml")
        let appleNameStringsURL = desktopURL.appendingPathComponent("AppleName.strings")
        let emojibaseURL = desktopURL.appendingPathComponent("emojibase.raw.json")
        for url in [emojiTestURL, cldrAnnotationsURL, appleNameStringsURL, emojibaseURL] {
            if !FileManager.default.fileExists(atPath: url.path) {
                fatalError("🔴 Couldn't find file: \(url.path)")
            }
        }
        // CLDR XML FILE OF ANNOTATIONS ON EMOJI -- AND OTHER SYMBOLS
        guard let xmlParser = XMLParser(contentsOf: cldrAnnotationsURL) else {
            fatalError("Couldn't read \(cldrAnnotationsURL.path)")
        }
        
        xmlParser.delegate = self
        xmlParser.parse()
        
        // SPECIAL FILE WITH CATEGORIES AND VARIATIONS OF EMOJI - SOMETIMES MULTIPLE VARIANTS PER EMOJI
        if let testContents = try? String(contentsOf: emojiTestURL, encoding: String.Encoding.utf8) {
            parseTestFile(contents: testContents)
        } else {
            fatalError("Couldn't read \(emojiTestURL.path)")
        }
        // APPLE NAMES DICT
        if let appleNamesContents = try? Data(contentsOf: appleNameStringsURL) {
            parseAppleNameDictionary(data: appleNamesContents)
        } else {
            fatalError("Couldn't read \(appleNameStringsURL.path)")
        }

        // Emojibase annotations
        if let emojibaseContents = try? Data(contentsOf: emojibaseURL) {
            parseEmojibaseDictionary(data: emojibaseContents)
        } else {
            fatalError("Couldn't read \(emojibaseURL.path)")
        }

    }
    
    // MARK: Output
    
    func saveFiles() {
        
        let annotationsOutputURL = desktopURL.appendingPathComponent("EmojiAnnotations-en.json")
        let categoriesOutputURL = desktopURL.appendingPathComponent("Categories.csv")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // keep the keys sorted so that a new version of this file isn't rearranged from previous
        
        do {
            let data = try encoder.encode(annotations)
            try data.write(to: annotationsOutputURL)
            print("🔵 SUCCESS: Wrote to \(annotationsOutputURL)")
        } catch {
            print(error)
        }
        
        do {
            let csvString: String = writeToCSVString()
            let csvData = csvString.data(using: .utf8)
            try csvData?.write(to: categoriesOutputURL)
            print("🔵 SUCCESS: Wrote to \(categoriesOutputURL)")
        } catch {
            print(error)
        }
    }
    
    func printReport() {
        var usedAnnotations = annotations
        print("\n\n🔵 LIST OF ALL EMOJIS")
        
        // Group first by number of skin tones
        for numSkinTonesIndex in ToneSupport.allCases {
            print("\n🔵 Emoji with \(numSkinTonesIndex) skin tone\(numSkinTonesIndex.rawValue == 1 ? "" : "s")")
            
            for group in Self.emojiFullGroups {
                if numSkinTonesIndex == .none {
                    print("\n🔵     CATEGORY: \(group.groupName)")    // only show by group for zero skintones
                }
                for emoji: EmojiFullInfo in group.emojis {
                    guard emoji.toneSupport == numSkinTonesIndex else { continue }        // ignore all but desired # of skin tones
                    
                    if let version: Double = emoji.version,
                       version > Self.latestSupportedEmojiVersion {  // Only point out here if it's newer than the latest released emoji
                        let versionString = String(format:"%.1f", version)
                        print("V: \(versionString) ", terminator: "")
                    }                
                    
                    print("\(emoji.string) ", terminator: "")
                    switch emoji.toneSupport {
                    case .none:
                        break
                    case .one:
                        for tone: SkinTone in SkinTone.allCases {
                            let toned = emoji.string.addingOneSkinTone(tone)
                            print(toned, terminator: "")
                            confirmFindBaseEmojiWorks(toned: toned, baseEmoji: emoji.string)
                        } 
                    case .two:
                        for tone: SkinTone in SkinTone.allCases {
                            for tone2: SkinTone in SkinTone.allCases {
                                
                                guard let toneBaseString = emoji.toneBaseString else {
                                    fatalError("missing template for 2 skin tones")
                                }
                                // Note: For women/woman and man/men holding hands, it's legal to use the one skin tone for when the
                                // skin tones are the same! However it seems find to use the 2-tone variation with just the same value
                                // so let's do this to make things simpler.
                                let withTwoTones = toneBaseString.replacingSkinTones(tone, tone2)
                                confirmFindBaseEmojiWorks(toned: withTwoTones, baseEmoji: emoji.string)
                                print(withTwoTones, terminator: "")
                            }
                            print(" ", terminator: "")
                        } 
                    }
                    if let annotations: [String] = annotations[emoji.string] {
                        usedAnnotations.removeValue(forKey: emoji.string)
                        
                        let strings: String = (annotations as NSArray).componentsJoined(by: " / ")
                        print("; \(strings)", terminator: "")
                    } else {
                        fatalError("Missing annotation for \(emoji.string)")
                    }
                    print("")
                }
            }
        }
        
        // This should be empty!
        if usedAnnotations.count > 0 {
            fatalError("Annotations left over that weren't looked up, should be none here: \(usedAnnotations.keys)")
        }
    }
    
    private func confirmFindBaseEmojiWorks(toned: String, baseEmoji actualBaseEmoji: String) {
        // Verify that algorithm to go from toned back to base emoji works!
        guard let foundBaseEmoji = EmojiList.sharedInstance.findBaseEmoji(for: toned) else {
            print("\n ⭕️ from toned \(toned) \(toned.dumpScalars)"
                  + " going back to untoned, NOT FOUND"
                  + " should be \(actualBaseEmoji) \(actualBaseEmoji.dumpScalars)... FAILED")
            return
        }
        guard foundBaseEmoji == actualBaseEmoji else {
            print("\n ⭕️ from toned \(toned) \(toned.dumpScalars)"
                  + " going back to untoned, was \(toned) \(toned.dumpScalars)"
                  + " should be \(actualBaseEmoji) \(actualBaseEmoji.dumpScalars)... FAILED")
            return
        }
    }
    
    
    // MARK: Cross-referencing 
    
    fileprivate func crossReferenceSingle(_ emoji: EmojiFullInfo,
                                          _ appleNamesRemaining: inout [String: String],
                                          _ emojibasesRemaining: inout [String: Set<String>],
                                          _ hasPrintedAppleNamesHeader: inout Bool,
                                          _ group: EmojiFullGroup) {

        // stop words. Hand-picked by finding which words from a big Internet stopwords list were actually found, then paring it way down
        let stopWords: Set<String> = ["in", "for", "and", "a", "an", "its", "from", "on", "off", "with", "of", "or", "over", "as", "the", "at"]

        // Look for this emoji in AppleNames
        var appleName: String? = appleNames[emoji.string]
        if appleName != nil {
            appleNamesRemaining.removeValue(forKey: emoji.string)
        } else if let matchedFromUnqualified = appleNames.first(where: { (key: String, value: String) in
            emoji.unqualifieds.contains(key)
        }) {
            appleName = matchedFromUnqualified.value
            appleNamesRemaining.removeValue(forKey: matchedFromUnqualified.key)

            // Last ditch: There are several emoji in AppleNames that have FE0F in them even though it's not specified as fully-qualified!
            // Let's see if we can add the FE0F and see if we can match it there.

        } else if let matchedFromAddingVariationSelector = appleNames[emoji.string.addedVariationSelector] {
            appleName = matchedFromAddingVariationSelector
            appleNamesRemaining.removeValue(forKey: emoji.string.addedVariationSelector)
        } else {
            if (emoji.version ?? 0) <= Self.latestSupportedEmojiVersion {
                // Don't complain if it's in a version of emoji which we know isn't listed here yet.
                let values = emoji.string.dumpScalars
                if !hasPrintedAppleNamesHeader {
                    print("""
                                🔵 APPLE NAMES CROSS-REF: Ignoring newer than \(Self.latestSupportedEmojiVersion). \
                                Several minor flags and a few others have been noted to be lacking in AppleNames; \
                                it's not clear why...
                                """)
                    hasPrintedAppleNamesHeader = true
                }
                print("🔵 \(emoji.string) \(values) '\(emoji.info)' NOT FOUND in AppleNames ")
                /*
                 Several minor flags are not listed in AppleNames - no biggie.

                 Also these - Not easy to confirm. I do see we have 1f4ac speech bubble but not left speech bubble. Oh well.
                 Female/Male just missing!
                 🗨️ 1F5E8 FE0F 'left speech bubble' NOT FOUND in AppleNames
                 ♀️ 2640 FE0F 'female sign' NOT FOUND in AppleNames
                 ♂️ 2642 FE0F 'male sign' NOT FOUND in AppleNames
                 */
            }
        }

        // Look for this emoji in Emojibase
        var emojibaseSet: Set<String>? = emojibases[emoji.string]
        if emojibaseSet != nil {
            emojibasesRemaining.removeValue(forKey: emoji.string)
        } else if let matchedFromUnqualified = emojibases.first(where: { (key: String, value: Set<String>) in
            emoji.unqualifieds.contains(key)
        }) {
            emojibaseSet = matchedFromUnqualified.value
            emojibasesRemaining.removeValue(forKey: matchedFromUnqualified.key)
        } else {
            if (emoji.version ?? 0) <= Self.latestSupportedEmojiVersion {
                // Don't complain if it's in a version of emoji which we know isn't listed here yet.
                let values = emoji.string.dumpScalars
                if emoji.version ?? 0 == 15.0 {
                    print("🔵 \(emoji.string) \(values) '\(emoji.info)' Emojibase doesn't support Emoji 15.0 yet; that's OK")
                } else {
                    print("🔵 \(emoji.string) \(values) '\(emoji.info)' NOT FOUND in Emojibase - This is not expected!")
                }
            }
        }

        // We have emoji.info and appleName and emojibase(s) already
        var annotationsFromXML: [String]?

        // First lookup, by main fully-qualified emoji string
        if let foundAnnotations: [String] = initialAnnotations[emoji.string] {
            annotationsFromXML = foundAnnotations
            initialAnnotations.removeValue(forKey: emoji.string)

            // Second try: by unqualified versions of the emoji which might match the XML file
        } else if let matchingKeyValue = initialAnnotations.first(where: { emoji.unqualifieds.contains($0.key) } ) {

            annotationsFromXML = matchingKeyValue.value
            // Remove the OLD annotation, with the wrong key, from our dictionary, before replacing with new key
            initialAnnotations.removeValue(forKey: matchingKeyValue.key)
        }

        // Handle flags specially; not in our annotations, so use English name.
        else if group.groupName == "Flags" {
            // appleName and emoji.info are very similar so tweak the apple name to resemble as much as possible to avoid near-duplication.
            if let originalAppleName = appleName {
                appleName = originalAppleName
                    .replacingOccurrences(of: "flag of the", with: "flag:")
                    .replacingOccurrences(of: "flag of", with: "flag:")
                    .replacingOccurrences(of: "Saint ", with: "St. ")
                    .replacingOccurrences(of: " the ", with: " ")
                    .replacingOccurrences(of: " US ", with: " U.S. ")
            }
        }

        // Build annotations out of, in this order of precedence:
        // annotationsFromXML     // highest priority since it's newest inclusive term
        // appleName
        // moreAnnotationsFromXML
        // emojibase
        // emoji.info - last fallback
        var possibleAnnotations: [String] = annotationsFromXML ?? []

        if let appleName = appleName {
            let appleNameLowercased = appleName.lowercased()
            possibleAnnotations.append(appleName)
        }

        if let emojibaseSet = emojibaseSet {
            let cleanedEmojibaseArray = Array(emojibaseSet).map { $0.lowercased().replacingOccurrences(of: "_", with: " ") }
            possibleAnnotations.append(contentsOf: cleanedEmojibaseArray)
        }

        possibleAnnotations.append(emoji.info)

        let mainAnnotation: String = possibleAnnotations.first! // always keep the first term intact - this will be the main annotation

        let separators: CharacterSet = CharacterSet(charactersIn: " “”(),:")

        let lowercasedAlreadyUsing = mainAnnotation.lowercased().components(separatedBy: separators).filter { word in !word.isEmpty }
        var searchTerms: [String] = []
        for phraseCandidate in possibleAnnotations.dropFirst() {
            for word in phraseCandidate.components(separatedBy: separators).filter({ word in !word.isEmpty }) {
                let wordLowercased = word.lowercased()
                if !stopWords.contains(wordLowercased),
                   !lowercasedAlreadyUsing.contains(wordLowercased),
                   !searchTerms.contains(wordLowercased) {
                    searchTerms.append(word)
                }
            }
        }
        if searchTerms.isEmpty {
            annotations[emoji.string] = [mainAnnotation] // store modified item back into dictionary
        } else {
            let searchTermsJoined = searchTerms.joined(separator: " ")
            annotations[emoji.string] = [mainAnnotation, searchTermsJoined] // store modified item back into dictionary
        }
    }

    func crossReference() {
        
        var appleNamesRemaining = appleNames
        var emojibasesRemaining = emojibases
        var hasPrintedAppleNamesHeader = false
        
        for group in Self.emojiFullGroups {
            for emoji in group.emojis {
                crossReferenceSingle(emoji, &appleNamesRemaining, &emojibasesRemaining, &hasPrintedAppleNamesHeader, group)
            }
        }

        // Check for problems
        
        print("\n\n🔵 Remaining appleNames not matched in our lists.")
        print("👩‍🤝‍👨👨‍🤝‍👨👩‍🤝‍👩🫱‍🫲 are known and inconsequential; they use a long 2-skintone variation when emoji-test has the short one.")
        for (emoji, text) in appleNamesRemaining {
            let values = emoji.dumpScalars
            print("   \(emoji) \(values) '\(text)'")
        }
        /*
         What remains in AppleNames that we haven't otherwise found:
         👨‍🤝‍👨 1F468 200D 1F91D 200D 1F468 'men holding hands'
         👩‍🤝‍👨 1F469 200D 1F91D 200D 1F468 'woman and man holding hands'
         👩‍🤝‍👩 1F469 200D 1F91D 200D 1F469 'women holding hands'
         🫱‍🫲 1FAF1 200D 1FAF2 'handshake'
         
         This is like: MAN + ZWJ + HANDSHAKE + ZWJ + MAN
         which is equivalent to people holding hands with skin tone, but we're not specifying the skin tone.
         However all we need, from emoji-test.txt, are 1F46B, 1F46C, 1F46D: W+M holding hands, men holding hands, women holding hands.
         Not sure which one is preferred or why these don't match but it really doesn't matter AFAIK.
         */
    }
    
    // MARK: AppleName parsing
    
    func parseAppleNameDictionary(data: Data) {
        if let parsed = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:String] {
            appleNames = parsed
        }
    }

    func parseEmojibaseDictionary(data: Data) {
        if let parsed = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject] {
            var newDictionary: [String: Set<String>] = [:]
            for (key, value) in parsed {
                var stringSet: Set<String>
                if let stringValue = value as? String {
                    stringSet = [stringValue]
                } else {
                    stringSet = Set(value as? [String] ?? [])
                }
                var updatedStringSet: Set<String> = stringSet
                for string in stringSet {

                    //*  - Emoji that are SUFFIXED with "face" should have a shortcode
                    //*    with the face suffix, and another shorthand equivalent.
                    //*    Example: "worried_face", "worried"
                    if string.hasSuffix("_face") {  // 5 characters
                        updatedStringSet.insert(String(string.dropLast(5)))
                    }

                    //*  - Emoji in the form of "person <action>" should also include
                    //*    shortcodes without the person prefix, in which they denote
                    //*    verbs/nouns. Example: "person_swimming", "swimming", "swimmer"
                    if string.hasPrefix("person_") {    // 7 characters
                        updatedStringSet.insert(String(string.dropFirst(7)))
                    }
                }


                let emoji: String = key.components(separatedBy: dashCharacterSet)
                    .compactMap { UInt32($0, radix: 16) }
                    .compactMap { Unicode.Scalar($0) }
                    .string
                newDictionary[emoji] = updatedStringSet
            }
            emojibases = newDictionary
        }
    }

    private lazy var dashCharacterSet = CharacterSet(charactersIn: "-")

    // MARK: "Test file" parsing
    
    func parseTestFile(contents: String) {
        
        var currentEmoji: EmojiFullInfo?
        
        func finishParsingCurrentEmoji() {
            if let currentEmoji = currentEmoji {
                currentEmojiGroup?.emojis.append(currentEmoji)
            }
            currentEmoji = nil
        }
        
        var currentEmojiGroup: EmojiFullGroup?
        
        func finishParsingCurrentEmojiGroup() {
            finishParsingCurrentEmoji()
            if let currentEmojiGroup = currentEmojiGroup, currentEmojiGroup.groupName != "Component" {
                Self.emojiFullGroups.append(currentEmojiGroup)
            }
            currentEmojiGroup = nil
        }
        
        let lines: [String] = contents.components(separatedBy: .newlines).filter { line in !line.isEmpty }
        var groupName: String?
        var subgroupName: String?   // So far just using for special parsing
        
        for line in lines {
            if line.hasPrefix("#") {
                if let capturedEmojiGroup = line.captured(from: ###"# group: (.+)"###) {
                    groupName = capturedEmojiGroup
                    let supportsSkinTones: Bool = groupName == "People & Body"
                    subgroupName = nil  // changing group; make sure subgroup is cleared
                    finishParsingCurrentEmojiGroup()
                    // start a new group with empty emojis
                    currentEmojiGroup = EmojiFullGroup(groupName: groupName ?? "Unknown", emojis: [], supportsSkinTones: supportsSkinTones)     
                } else if let capturedSubgroup = line.captured(from: ###"# subgroup: (.+)"###) {
                    subgroupName = capturedSubgroup
                }
            } else {
                guard groupName != "Component" else { continue }
                let hex         = line[ 0...54].trimmingCharacters(in: .whitespaces)
                let qualified   = line[57...76].trimmingCharacters(in: .whitespaces)
                let emoji       = line[79...79].trimmingCharacters(in: .whitespaces)
                let versionInfo = line[82...999] // version like E2.0 followed by space, and then description which we'll ignore
                guard let whereSpace = versionInfo.range(of: " ") else {
                    print("⭕️ ERROR - NOT FINDING SPACE IN VERSION+INFO")
                    continue
                }
                
                // Handle Skin Tone(s)
                
                if let currentToneSupport = currentEmoji?.toneSupport,
                   let capturedSkinToneStrings: [String] = .some(hex.captured(from: ###"(1F3F[BCDEF]+)"###)),
                   capturedSkinToneStrings.count > 0,
                   qualified == "fully-qualified" {
                    // Mark that the currently scanned symbol also has skin tone variations. Keep the largest number.
                    currentEmoji?.toneSupport = ToneSupport(rawValue: max(currentToneSupport.rawValue, capturedSkinToneStrings.count)) ?? .none
                    
                    // For two skintones - look for this combo, which is one of the variations listed that has two separate tones.
                    // We will use this particular (arbitrary) combination as the starting point then replace with the actual two tones we need.
                    if nil != versionInfo.range(of: " light skin tone, dark skin tone") {
                        currentEmoji?.toneBaseString = emoji
                    }
                    
                    // Verify that our emoji toning algorithms work
                    let skinTones: [SkinTone] = capturedSkinToneStrings.map({SkinTone(rawValue: UInt32($0, radix: 16) ?? 0)}).compactMap({$0})
                    if capturedSkinToneStrings.count == 1, let skinTone: SkinTone = skinTones.first, let baseString = currentEmoji?.string   {
                        let generatedToned = baseString.addingOneSkinTone(skinTone)
                        if generatedToned != emoji {
                            print("⭕️ Given one-toned \(emoji) \(emoji.dumpScalars) != generated \(generatedToned) \(generatedToned.dumpScalars)")
                        }
                    } else if capturedSkinToneStrings.count == 2, let baseString = currentEmoji?.toneBaseString   {
                        let generatedToned = baseString.replacingSkinTones(skinTones[0], skinTones[1])
                        if generatedToned != emoji {
                            print("⭕️ Given two-toned \(emoji) \(emoji.dumpScalars) != generated \(generatedToned) \(generatedToned.dumpScalars)")
                        }
                    } 
                    
                } else {
                    let versionString: String = versionInfo.substring(to: whereSpace.lowerBound)
                    let version: Double?
                    if let convertedVersion: Double = Double(versionString) {
                        // We only care about unicode version 12.0 and up.
                        version = convertedVersion >= 12.0 ? convertedVersion : nil 
                    } else {
                        print("⭕️ ERROR - VERSION NOT FOUND in \(line)")
                        version = nil
                    }
                    var versionForTones: Double? = nil  // Generally nil unless overridden
                    let info: String = versionInfo.substring(from: whereSpace.upperBound)
                    if qualified == "fully-qualified" {
                        finishParsingCurrentEmoji()        // Starting a new EmojiFullInfo
                        var repairedEmoji: String = emoji
                        var unqualifieds: Set<String> = []
                        if subgroupName == "zodiac" && emoji != "⛎" {
                            print("🔵 Upgrading zodiac \(emoji.dumpScalars) to '\(repairedEmoji)' to force it to always be rendered as emoji")
                            // Though the test file says zodiac files without FEOF are fully-qualified, the AppleNames file has them,
                            // which gives them the emoji look! So let's "repair" these.
                            repairedEmoji = emoji.addedVariationSelector
                            unqualifieds = [emoji]  // put the original into the unqualifieds list so we will find in annotations
                        }
                        if info == "handshake" {
                            print("🔵 Special override: '\(emoji)' marked that Emoji 14.0 is required to render skin tones.")
                            versionForTones = 14.0       // special case
                        }
                        currentEmoji = EmojiFullInfo(string: repairedEmoji,
                                                     toneSupport: .none,
                                                     version: version,
                                                     versionForTones: versionForTones,
                                                     unqualifieds: unqualifieds,
                                                     info: info)    // unqualifieds, supportsSkinTones may be updated in subsequent lines
                    } else {
                        currentEmoji?.unqualifieds.insert(emoji)
                    }
                }
            }
        }
        finishParsingCurrentEmojiGroup()
    }
    
    // MARK: XML annotations parsing
    
    var currentEmoji: String?               // Current emoji being parsed. When we find a new one, save the previous one in annotations
    var currentTTS: String = ""
    var currentAnnotationsSeparated: String = ""
    var isAnnotationTTS: Bool = false
    
    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        guard elementName == "annotation" else { return } 
        let type: String? = attributeDict["type"]       // may be tts; it's a duplicate of character but a TTS label for it
        guard let cp: String = attributeDict["cp"] else {
            print("⭕️ Missing cp attribute")
            return
        }
        
        if cp != currentEmoji {
            finishCurrentEmoji()
            self.currentEmoji = cp
        }
        isAnnotationTTS = type == "tts"     // where upcoming annotation will go
    }
    
    func finishCurrentEmoji() {
        guard let currentEmoji = currentEmoji else { return }
        // Remove TTS key; that's redundant
        var alt: [String] = currentAnnotationsSeparated.components(separatedBy: " | ").filter({$0 != currentTTS})
        
        if let additionalEnglish = additionalEnglishTerms[currentEmoji] {
            alt.append(contentsOf: additionalEnglish)
        }
        
        initialAnnotations[currentEmoji] = [currentTTS] + alt
        currentAnnotationsSeparated = ""
        currentTTS = ""       // Clear these out in preparation for following elements
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if isAnnotationTTS {
                currentTTS += string          // Append string since we may get several calls of this
            } else {
                currentAnnotationsSeparated += string
            }
        }
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        finishCurrentEmoji()
    }
    
    // MARK: CSV Output
    
    func writeToCSVString() -> String {
        let groups: [String] = Self.emojiFullGroups.map { 
            
            let emojiLines: [String] = $0.emojis.map {
                let lineComponents: [String] = [$0.string, 
                                                $0.toneSupport == .one ? "1" : ($0.toneSupport == .two ? ($0.toneBaseString ?? "") : ""),
                                                $0.version.flatMap({$0.asCompactString}) ?? "",
                                                $0.versionForTones.flatMap({$0.asCompactString}) ?? ""]
                let joinedWithComma: String = (lineComponents as NSArray).componentsJoined(by: ",")
                let trimmed = joinedWithComma.replacingOccurrences(of: ",+$", with: "", options: .regularExpression) // remove empty fields at end
                return trimmed
            }
            
            return $0.groupName 
            + ($0.supportsSkinTones ? ",1" : "")
            + "\n"
            + (emojiLines as NSArray).componentsJoined(by: "\n")
        }
        let result: String = (groups as NSArray).componentsJoined(by: "\n\n")
        return result
    }
}

extension Double {
    
    // We want to output the double with zero or one places. This seems to be the best way to ensure that.
    private static var compactStringFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = ""
        return formatter
    }()
    
    var asCompactString: String {
        let number = NSNumber(value: self)
        return Self.compactStringFormatter.string(from: number)!
    }
}


// MARK: - Parsing Support

private extension StringProtocol where Index == String.Index {
    func ranges<T: StringProtocol>(of string: T, options: String.CompareOptions = []) -> [Range<Index>] {
        var ranges: [Range<Index>] = []
        var start: Index = startIndex
        
        while let range = range(of: string, options: options, range: start..<endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        
        return ranges
    }
}

private extension String {
    
    func captured(from pattern: String) -> String? {
        var result: String?
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsrange = NSRange(self.startIndex..<self.endIndex, in: self)
            regex.enumerateMatches(in: self, options: [], range: nsrange) { (match, _, stop) in
                if let match = match, let firstCaptureRange = Range(match.range(at: 1), in: self) {
                    result = String(self[firstCaptureRange])
                }
            }
        }
        return result
    }
    
    func captured(from pattern: String) -> [String] {
        var result: [String] = []
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsrange = NSRange(self.startIndex..<self.endIndex, in: self)
            regex.enumerateMatches(in: self, options: [], range: nsrange) { (match, _, stop) in
                if let match = match, let captureRange = Range(match.range(at: 1), in: self) {  // get the captured skin-tone phrase
                    result.append(String(self[captureRange]))
                }
            }
        }
        return result
    }
    
    subscript(bounds: CountableClosedRange<Int>) -> String {
        let lowerBound = max(0, bounds.lowerBound)
        guard lowerBound < self.count else { return "" }
        
        let upperBound = min(bounds.upperBound, self.count-1)
        guard upperBound >= 0 else { return "" }
        
        let i = index(startIndex, offsetBy: lowerBound)
        let j = index(i, offsetBy: upperBound-lowerBound)
        
        return String(self[i...j])
    }
    
    subscript(bounds: CountableRange<Int>) -> String {
        let lowerBound = max(0, bounds.lowerBound)
        guard lowerBound < self.count else { return "" }
        
        let upperBound = min(bounds.upperBound, self.count)
        guard upperBound >= 0 else { return "" }
        
        let i = index(startIndex, offsetBy: lowerBound)
        let j = index(i, offsetBy: upperBound-lowerBound)
        
        return String(self[i..<j])
    }
    
    var dumpScalars: String {
        return unicodeScalars.map({$0.value}).map({String(format:"%04X", $0)}).joined(separator: " ")
    }
}

// MARK: - Stub implementation of EmojiList

/// For this project, we define the EmojiList so we can test our reverse skin-tone lookup.
/// Client app will probably want to load and cache the emoji list from disk, and provide additional functionality.
/// For this project, we use the list that is parsed from the emoji source data.

class EmojiList: EmojiListProtocol {
    
    static var sharedInstance: EmojiListProtocol = EmojiList()
    private init() {} // This prevents others from using the default '()' initializer for this class.
    
    lazy var allEmojiGroups: [EmojiGroup] = {
        let newGroups: [EmojiGroup] = EmojiParser.emojiFullGroups.map({
            let newEmojis: [EmojiInfo] = $0.emojis.map({
                EmojiInfo(string: $0.string, toneSupport: $0.toneSupport, toneBaseString: $0.toneBaseString)
            })
            return EmojiGroup(groupName: $0.groupName, emojis: newEmojis, supportsSkinTones: $0.supportsSkinTones)
        })
        return newGroups
    }()
}
