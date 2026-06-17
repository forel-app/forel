import Testing
import Foundation
@testable import ForelCore

@Suite struct RuleEngineTests {
    @Test func evaluateFileMatchesEnabledRulesWithAllOrAnyConditions() throws {
        let dir = TempDir()
        let file = dir.file("invoice.pdf", contents: "paid")
        let rules = [
            makeRule(name: "all matched", conditionMatch: .all, conditions: [
                makeCondition(.name, .contains, "invoice"),
                makeCondition(.extension_, .is, "pdf"),
            ]),
            makeRule(name: "any matched", conditionMatch: .any, conditions: [
                makeCondition(.name, .contains, "receipt"),
                makeCondition(.contents, .contains, "paid"),
            ]),
            makeRule(name: "disabled", enabled: false, conditions: [makeCondition(.extension_, .is, "pdf")]),
            makeRule(name: "empty"),
        ]

        let (matched, history) = RuleEngine.evaluateFile(path: file, depth: 0, rules: rules, batchId: "batch")
        #expect(matched == ["all matched", "any matched", "empty"])
        #expect(history.isEmpty)
    }

    @Test func previewFileHidesAlreadyAppliedActions() throws {
        let dir = TempDir()
        let file = dir.file("photo.jpg", contents: "img")
        var rule = makeRule(name: "label jpgs", conditions: [makeCondition(.extension_, .is, "jpg")])
        rule.actions = [
            makeAction(.setColorLabel, .object(["color": .string("Yellow")]), position: 1),
            makeAction(.addTag, .object(["tags": .stringArray(["Sorted"])]), position: 2),
        ]

        let before = RuleEngine.previewFile(path: file, depth: 0, rules: [rule])
        #expect(before?.rules[0].actions.count == 2)

        let (_, history) = RuleEngine.evaluateFile(path: file, depth: 0, rules: [rule], batchId: "batch")
        #expect(history.count == 2)
        #expect(history.allSatisfy { $0.reversible })
        #expect(RuleEngine.previewFile(path: file, depth: 0, rules: [rule]) == nil)
    }

    @Test func previewFileReturnsOrderedActionsWithoutExecutingThem() throws {
        let dir = TempDir()
        let file = dir.file("invoice.pdf", contents: "paid")
        let destination = dir.dir("Processed")
        var rule = makeRule(name: "archive invoice", conditions: [makeCondition(.extension_, .is, "pdf")])
        rule.actions = [
            makeAction(.addTag, .object(["tag": .string("Reviewed")]), position: 2),
            makeAction(.moveToFolder, .object(["destination": .string(destination)]), position: 1),
        ]

        let preview = RuleEngine.previewFile(path: file, depth: 0, rules: [rule])
        #expect(preview != nil)
        #expect(FileManager.default.fileExists(atPath: file))
        #expect(!FileManager.default.fileExists(atPath: (destination as NSString).appendingPathComponent("invoice.pdf")))
        #expect(preview?.name == "invoice.pdf")
        #expect(preview?.rules[0].ruleName == "archive invoice")
        #expect(preview?.rules[0].actions == [
            "Move to \((destination as NSString).appendingPathComponent("invoice.pdf"))",
            "Add tag 'Reviewed'",
        ])
    }

    @Test func recursionDepthBlocksNestedMatchesButAllowsDirectChildren() throws {
        let dir = TempDir()
        let direct = dir.file("direct.txt", contents: "direct")
        let nestedDir = dir.dir("Nested")
        let nested = (nestedDir as NSString).appendingPathComponent("inside.txt")
        try "nested".write(toFile: nested, atomically: true, encoding: .utf8)

        let shallowRule = makeRule(name: "shallow", conditions: [makeCondition(.name, .contains, "direct")], recursionDepth: 0)

        #expect(RuleEngine.evaluateFile(path: direct, depth: 0, rules: [shallowRule], batchId: "batch").matched == ["shallow"])
        #expect(RuleEngine.evaluateFile(path: nested, depth: 1, rules: [shallowRule], batchId: "batch").matched == [])
    }

    @Test func pathDepthComputesRelativeDepthFromRoot() throws {
        #expect(RuleEngine.pathDepth(root: "/Users/x/Inbox", path: "/Users/x/Inbox/file.txt") == 0)
        #expect(RuleEngine.pathDepth(root: "/Users/x/Inbox", path: "/Users/x/Inbox/Sub/file.txt") == 1)
        #expect(RuleEngine.pathDepth(root: "/Users/x/Inbox", path: "/Users/x/Other/file.txt") == nil)
    }
}
