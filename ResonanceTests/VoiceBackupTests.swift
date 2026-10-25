//
//  VoiceBackupTests.swift
//  ResonanceTests
//
//  "Back up my voice": safe file names and a real archive built from test files.
//

import Testing
import Foundation
@testable import Resonance

struct VoiceBackupTests {
    @Test func namesAreNumberedAndReadable() {
        #expect(VoiceBackup.exportName(label: "I love you", index: 3) == "03 I love you.m4a")
        #expect(VoiceBackup.exportName(label: "I'm thirsty", index: 12) == "12 I'm thirsty.m4a")
    }

    @Test func reservedCharactersAndDotsAreRemoved() {
        #expect(VoiceBackup.exportName(label: "Yes/No: maybe?", index: 1) == "01 Yes No maybe.m4a")
        #expect(VoiceBackup.exportName(label: "...hidden", index: 1) == "01 hidden.m4a")
        #expect(VoiceBackup.exportName(label: "  ", index: 2) == "02 Recording.m4a")
        #expect(VoiceBackup.exportName(label: "Line\nbreak", index: 4) == "04 Line break.m4a")
    }

    @Test func longLabelsAreShortened() {
        let name = VoiceBackup.exportName(label: String(repeating: "a", count: 200), index: 1)
        #expect(name.count == 3 + VoiceBackup.maxNameLength + 4)
    }

    @Test func folderNameHasTheDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
        #expect(VoiceBackup.folderName(date: date, calendar: calendar) == "Resonance voice backup 2026-10-04")
    }

    @Test func archiveIsMadeAndMissingFilesAreSkipped() throws {
        let fm = FileManager.default
        let bank = fm.temporaryDirectory.appendingPathComponent("BankTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: bank, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: bank) }
        try Data(repeating: 1, count: 2_000).write(to: bank.appendingPathComponent("a.m4a"))

        let url = try VoiceBackup.makeArchive(items: [.init(fileName: "a.m4a", label: "Hello"),
                                                     .init(fileName: "missing.m4a", label: "Gone")],
                                              bankDirectory: bank)
        defer { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        #expect(url.pathExtension == "zip")
        let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 0)
    }

    @Test func nothingToBackUpIsAnError() {
        #expect(throws: VoiceBackup.BackupError.self) {
            try VoiceBackup.makeArchive(items: [], bankDirectory: FileManager.default.temporaryDirectory)
        }
    }
}
