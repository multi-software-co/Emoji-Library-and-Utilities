# Remotion Emoji Library & Utilities

[![Emoji Version - 15.0](https://img.shields.io/badge/Emoji_Version-15.0-2ea44f)](https://unicode.org/Public/emoji/15.0/emoji-test.txt)



## Purpose

Getting a complete list of supported (in whatever OS you are running) emoji, and their annotations for tooltips (with additional annotations for searching), and that support skin tones, is a nontrivial problem.  The sample code that you are likely to find online might be just some simple single-code points that skip large numbers of emoji that are created by combining several characters. Other repositories you might find online aren't up-to-date with the latest versions of Unicode and the Emoji set.

The approach that this repository uses is to go to the original sources of emoji characters (Unicode.org) and the CLDR (Common Locale Data Repository) for the annotations. We also, for good measure, cross-reference with Apple's internal annotation dictionary to enhance the searchable keywords and look for inconsistencies and MacOS (and iOS?) overrides.

One challenge is that many emoji can have multiple variations in how they are expressed that are not visible to the human eye, and that the emoji
specified in these three sources we are scanning are inconsistent. Therefore we need to adjust many of the characters to be "fully qualified" as
the canonical versions. (There are a few exceptions such as Zodiac signs, to force them to render as emoji rather than plain characters.)

The data files included in this repository are the latest versions of emoji, and include version information so your application can make sure that your OS will support the emoji you want to use.

<p align="center" width="100%">
    <img width="33%" src="readme-images/handshake.png" alt="Handshake with two different skin tones">
</p>

## Future Maintenance

Check back on this repository after a new version of Emoji is released for the latest data updates. Or, update the data files and run this again when there is a new version of Unicode/Emoji released or announced. Be sure to test and look for inconsistencies that might need to be adjusted.
Also, do this when Apple updates MacOS and there is new support for newer version of Unicode in the OS. (See instructions further down.)

## Instructions

The easiest way to make use of this repository is to just include this package as a dependency using Swift Package Manager and including the **EmojiUtilities** product as a dependency by adding `.product(name: "EmojiUtilities", package: "Emoji-Library-and-Utilities"),` to your target. Then use `loadEmojiGroups` (more info below) to parse and load the emojis into your project.

## The Data Files

### EmojiAnnotations-en.json
A dictionary keyed by supported emoji (without any skin tones applied), for looking up tooltip and matching search queries.
Each entry in dictionary is a dictionary:
* key is the emoji string
* value is an array of strings for emoji. First one is main annotation for tooltip; others suitable for searching.

### Categories.csv
An ordered list of emoji categories, and with in each category, an ordered list of emojis.

The first line in the file, and each line after an empty line, is a "header" for a group. A header line contains these comma-separated fields:
* Group name
* optional: "1" to indicate that this group has skin tone support. (Really it can be any non-empty string.)

Each line after the group header, until an empty line is found, is an emoji record for that group, with these comma-separated fields:
* The emoji, no skin tones applied
* Empty for no skin toning; "1" if this emoji supports 1 skin tone; If it supports 2 skin tones, it's the "base" emoji to swap in the two colors used by our EmojiUtilities code.
* Empty, or Minimum emoji version, for version 12.0 and up. Remove any emoji not supported in your OS.
* Empty, or Minimum emoji version, for this emoji to have skin tone support. Specifically to support "🤝" which is supported universally in the generic yellow color but requires Emoji 14.0 for skin tones.

When loading into the client, be sure to ignore emoji that aren't compatible with your OS, and also disable skin tones for incompatible OS versions. The code in EmojiUtilities.swift takes care of this.

---
## EmojiUtilities.swift

This file contains several structures and methods we use for parsing and manipulating emoji as read from Categories.csv.

It currently supports up to Emoji 15.0; please update `emojiVersionSupportedInThisOSVersion` when a new version of MacOS has been released or announced that will support a subsequent version.

`protocol EmojiListProtocol`
* Implement this protocol to load the emojis from disk and maintain a list of categories, each containing emoji.
* Through an extension, this file implements these methods:
    * `func findBaseEmoji(for tonedEmoji: String) -> String?`
      * Brute force searches for base emoji from a toned emoji by looking for probable matches from the first character and then applying that tone until a match is found. Not called often so it's OK that it's inefficient!

    * `func findEmojiInfo(for emoji: String) -> EmojiInfo?`
      * Brute force searches for EmojiInfo record from a (toned or untoned) emoji by looking for probable matches from the first character

`enum SkinTone`
* Representation of emoji skin tones for human figures: light, mediumLight, medium, mediumDark, and Dark.

`struct EmojiGroup`
* A group of emoji with its name and a list of emoji in that group. Also contains flag to indicate if skin tones are supported in this group.
* `func loadEmojiGroups() -> [EmojiGroup]`
   * Utility method to load emojis from the included **Categories.csv** file.

* `func loadEmojiGroupsFrom(string dataString: String) -> [EmojiGroup]`
   * Utility method to load emojis from a string of emoji information you provide.

`struct EmojiInfo`
* A single emoji string with information about skin-tone support.

`enum ToneSupport`
* Whether an emoji supports no skin tones (most of them), one skin tone (most of the people emojis), or two skin tones (just a few of these)

`extension String`
* Several utilities which operate on a String that represents an emoji:
   * `addedVariationSelector: String { get }`
      * Add Variation Selector 0xFE0F to make a non-emoji into an emoji when applicable
   * `func addingOneSkinTone(_ tone: SkinTone) -> String`
      * For an emoji that supports a single skin tone, converts the "base" (toneless) emoji to the given skin tone.
   * `func replacingSkinTones(_ tone: SkinTone, _ tone2: SkinTone) -> String`
      * For an emoji that supports two skin tones. It converts the two-tone emoji that is that starting point into using the desired tones.


<p align="center" width="100%">
    <img width="437" src="readme-images/multi-tone-handshake.png" alt="Several different handshakes with multiple skin tones">
</p>

---

## Generating new data files from source data

If you want to generate your own emoji list, either with an updated Emoji version or to adjust what gets created, then run this project to generate the data files mentioned above.

Download & prepare the files listed below (1, 2, 3) and place on your Desktop. 

Then open up "Package.swift" (instead of a project file!) and choose the "GenerateEmoji" target. Run the tool from Xcode.

The output includes a bunch of diagnostic output to help look for inconsistencies. Some inconsistencies are OK as long as they are worked around.
Make sure that the skin tones look as expected - if the emoji version is greater than what's supported by the current OS, expect to see oddities!

### CLDR

[The latest annotations file from CLDR (Common Locale Data Repository)](https://github.com/unicode-org/cldr/blob/main/common/annotations/en.xml)

* Currently this goes up to Unicode 15.0.
* This is English; we could maybe have different versions for other languages.
* The "tts" lines indicate the main annotation to use (e.g. tooltips); the other strings are good for searching.
* Note that this also contains non-emoji characters (like symbols) so we need to filter those out using the list below. Also, many of the characters are encoded in a not "fully-qualified" way, so our cross-referencing has to repair this.
* This doesn't contain flags, so we get those annotations from the other files.

### Emoji List

For the categories, an ordered list of all supported emoji, unicode versions, and skin-tone variations, we parse the [latest version of this file](https://unicode.org/Public/emoji/latest/emoji-test.txt). (Note that this links to the latest *released* version, so there may be a newer version than this.)

### Shortcodes (a.k.a. emoji cheat sheet)

The [Emojibase shortcodes list](https://emojibase.dev/shortcodes/?shortcodePresets=emojibase&genders=false) seems to be the best-maintained of several similar lists. 

We're using the [raw English json file](https://github.com/milesj/emojibase/blob/master/packages/data/en/shortcodes/emojibase.raw.json) to parse.

Also, [their shortcodes list](https://github.com/milesj/emojibase/blob/master/packages/generator/src/resources/shortcodes.ts) has some rules about parsing.

Note that this only goes up to Emoji 14.0 so we're adding in our own unofficial Emoji 15 strings as a stop-gap.

### AppleName.strings

For additional descriptions, and just for cross-referencing, this is the list of unicode and their strings from MacOS.
The binary-formatted file is at:
`/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources/en.lproj/AppleName.strings`
It needs to be converted to json using `plutil -convert json AppleName.strings`.
From this file it is clear that Apple supports zodiac emoji that have purple badges, not just the characters listed in emoji-test.txt, so we
compensate for that.

---

## Emoji Documentation

[Emoji 15.0](https://emojipedia.org/emoji-15.0/) at Emojipedia

[Latest version of Emoji parsed is 15.0, from 2022; available in Ventura 13.3 and up.](https://unicode.org/emoji/charts/emoji-versions.html)
(Emoji 14.0 was bundled in MacOS 12.3; Emoji 13.0 was in Big Sur and Monterey through 12.2. Emoji 12.1 was in Catalina starting with 10.15.1 — I'm not sure about older OS versions.)

[This seems to be the master overview file](http://www.unicode.org/reports/tr51/); it's a good overview of the Emoji data. See [#emoji-data](http://www.unicode.org/reports/tr51/#emoji-data) for links to data files


## Ideas for improvements

* Programmatically check string lengths on all the emoji that are generated rather than just eyeballing them?
* I18n to allow tooltips and searching of the emoji in languages other than English

