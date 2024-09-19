//
//  BlockParser.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/18/24.
//
//  A simple parser for parsing the AI's output.
//

import Foundation

/// Extracts blocks delimited by markup tags from text. Only top-level tags are considered. 
///
/// For example, the text below:
/// ```
///     <block1>
///         <block1a></block1a>
///         <block1b>
///         </block1c>
///     </block1>
///     <block2><block2a></block2>
///     <block3></block3a></block3a><block3a>
/// ```
/// Would result in the following set of blocks:
/// ```
///     block1
///     block2
///     block3
/// ```
///
/// - Parameter from: Text to parse.
/// - Returns: Array of blocks, tag and contents.
func parseBlocks(from text: String) -> [(tag: String, contents: String)] {
    var result: [(tag: String, contents: String)] = []
    var currentIndex = text.startIndex
    var insideBlock = false
    var currentTag = ""
    var currentContents = ""

    // Tags consist of only alphanumeric characters and underscores
    func isValidTagCharacter(_ char: Character) -> Bool {
        return char.isLetter || char.isNumber || char == "_"
    }

    // Scan one character at a time for top-level tags (we don't consider nesting and treat nested
    // tags as regular content)
    while currentIndex < text.endIndex {
        let currentChar = text[currentIndex]

        if !insideBlock && currentChar == "<" {
            // Potential start of a tag
            var tagEndIndex = text.index(after: currentIndex)
            var potentialTag = ""

            // Validate the tag
            while tagEndIndex < text.endIndex && text[tagEndIndex] != ">" {
                if isValidTagCharacter(text[tagEndIndex]) {
                    potentialTag.append(text[tagEndIndex])
                    tagEndIndex = text.index(after: tagEndIndex)
                } else {
                    break
                }
            }

            if tagEndIndex < text.endIndex && text[tagEndIndex] == ">" && !potentialTag.isEmpty {
                // Valid opening tag found
                insideBlock = true
                currentTag = potentialTag
                currentContents = ""
                currentIndex = text.index(after: tagEndIndex)
                continue
            }
        } else if insideBlock {
            let closingTagStr = "</\(currentTag)>"
            if text[currentIndex...].hasPrefix(closingTagStr) {
                // Matching closing tag found
                result.append((tag: currentTag, contents: currentContents))
                insideBlock = false
                currentIndex = text.index(currentIndex, offsetBy: closingTagStr.count)
                continue
            } else {
                // Inside a block, add to contents
                currentContents.append(currentChar)
            }
        }

        currentIndex = text.index(after: currentIndex)
    }

    // If we ended inside of a block (no terminating </block>), output anyway
    if insideBlock {
        result.append((tag: currentTag, contents: currentContents))
    }

    return result
}
