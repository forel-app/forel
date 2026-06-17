import Testing
import Foundation
@testable import ForelCore

@Suite struct ConditionEvaluatorTests {
    @Test func sizeConditionComparesParsedThresholds() throws {
        let dir = TempDir()
        let file = dir.file("data.bin", contents: "1234567890")

        #expect(ConditionEvaluator.evaluate(makeCondition(.sizeBytes, .is, "10 bytes"), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.sizeBytes, .lessThan, "1 KB"), path: file))
    }

    @Test func tagConditionMatchesTrimmedCaseInsensitiveTagNames() throws {
        let dir = TempDir()
        let file = dir.file("document.txt", contents: "hello")
        _ = try ActionExecutor.execute(makeAction(.addTag, .object(["tag": .string("Project")])), path: file)

        #expect(ConditionEvaluator.evaluate(makeCondition(.tags, .is, " project "), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.tags, .contains, "roj"), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.tags, .matchesRegex, "^proj"), path: file))
    }

    @Test func colorLabelConditionMatchesFinderColorTagName() throws {
        let dir = TempDir()
        let file = dir.file("image.png", contents: "png")
        _ = try ActionExecutor.execute(makeAction(.setColorLabel, .object(["color": .string("Red")])), path: file)

        #expect(ConditionEvaluator.evaluate(makeCondition(.colorLabel, .is, "red"), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.colorLabel, .isNot, "blue"), path: file))
    }

    @Test func createdAtConditionHandlesAbsoluteAndRelativeOperators() throws {
        let dir = TempDir()
        let file = dir.file("fresh.txt", contents: "new")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let tomorrow = formatter.string(from: Date().addingTimeInterval(86400))
        let yesterday = formatter.string(from: Date().addingTimeInterval(-86400))

        #expect(ConditionEvaluator.evaluate(makeCondition(.createdAt, .withinLast, "1 day"), path: file))
        #expect(!ConditionEvaluator.evaluate(makeCondition(.createdAt, .olderThan, "1 year"), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.createdAt, .before, tomorrow), path: file))
        #expect(!ConditionEvaluator.evaluate(makeCondition(.createdAt, .after, tomorrow), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.createdAt, .after, yesterday), path: file))
        #expect(!ConditionEvaluator.evaluate(makeCondition(.createdAt, .withinLast, ""), path: file))
        #expect(!ConditionEvaluator.evaluate(makeCondition(.createdAt, .olderThan, "5 decades"), path: file))
    }

    @Test func dateModifiedConditionMatchesRecentFile() throws {
        let dir = TempDir()
        let file = dir.file("fresh.txt", contents: "new")

        #expect(ConditionEvaluator.evaluate(makeCondition(.dateModified, .withinLast, "1 day"), path: file))
        #expect(!ConditionEvaluator.evaluate(makeCondition(.dateModified, .olderThan, "1 year"), path: file))
    }

    @Test func kindConditionClassifiesCommonFileTypesAndDirectories() throws {
        let dir = TempDir()
        let pdf = dir.file("paper.pdf", contents: "%PDF")
        let image = dir.file("photo.heic", contents: "image")
        let archive = dir.file("backup.tar", contents: "archive")
        let folder = dir.dir("Folder")
        let app = dir.dir("Example.app")

        #expect(ConditionEvaluator.evaluate(makeCondition(.kind, .is, "pdf"), path: pdf))
        #expect(ConditionEvaluator.evaluate(makeCondition(.kind, .is, "image"), path: image))
        #expect(ConditionEvaluator.evaluate(makeCondition(.kind, .is, "archive"), path: archive))
        #expect(ConditionEvaluator.evaluate(makeCondition(.kind, .is, "folder"), path: folder))
        #expect(ConditionEvaluator.evaluate(makeCondition(.kind, .is, "application"), path: app))
    }

    @Test func nameAndExtensionConditionsMatchStringOperators() throws {
        let dir = TempDir()
        let file = dir.file("invoice.PDF", contents: "paid")

        #expect(ConditionEvaluator.evaluate(makeCondition(.name, .contains, "invoice"), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.extension_, .is, "pdf"), path: file))
        #expect(ConditionEvaluator.evaluate(makeCondition(.extension_, .is, ".pdf"), path: file))
    }
}
