//
//  VoiceBackup.swift
//  Resonance
//
//  "Back up my voice": packs every Voice Bank recording into one .zip with readable file
//  names ("03 I love you.m4a") and a short note, so the person can save it to Files,
//  iCloud Drive, a computer or a family member's phone. A banked voice can't be recorded
//  again once speech changes, so losing the phone must not mean losing the voice.
//  Nothing leaves the phone unless the person picks where to save it in the share sheet.
//  The naming logic is plain Swift, unit tested in VoiceBackupTests.
//

import Foundation

enum VoiceBackup {
    struct Item: Equatable {
        var fileName: String     // stored name, e.g. "<uuid>.m4a"
        var label: String        // the phrase, e.g. "I love you"
    }

    enum BackupError: LocalizedError {
        case nothingToBackUp
        case couldNotPack

        var errorDescription: String? {
            switch self {
            case .nothingToBackUp: return "There are no recordings to back up yet."
            case .couldNotPack: return "The backup couldn't be made. Please try again."
            }
        }
    }

    static let maxNameLength = 60

    /// A file name that is safe on every computer: no slashes or other reserved characters,
    /// no leading dots, a limited length, and a number so names never collide.
    static func exportName(label: String, index: Int, extension ext: String = "m4a") -> String {
        let reserved = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var cleaned = label.unicodeScalars.map { reserved.contains($0) ? " " : String($0) }.joined()
        cleaned = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.count > maxNameLength {
            cleaned = String(cleaned.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        }
        if cleaned.isEmpty { cleaned = "Recording" }
        return String(format: "%02d", index) + " " + cleaned + "." + ext
    }

    /// "Resonance voice backup 2026-10-24".
    static func folderName(date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "Resonance voice backup %04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The note saved next to the recordings.
    static func readme(count: Int, date: Date) -> String {
        """
        These \(count) recording\(count == 1 ? "" : "s") are my own voice, saved with Resonance on \(date.formatted(date: .long, time: .omitted)).

        Please keep them somewhere safe. They are ordinary audio files (.m4a) that play on any phone or computer.
        Voice banking and message banking services can use recordings like these to build a voice that sounds like me.
        """
    }

    /// Builds the .zip in a temporary folder and returns its location. Recordings whose file
    /// is missing are skipped. Runs file work only (call it off the main thread).
    static func makeArchive(items: [Item], bankDirectory: URL, date: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let present = items.filter { fm.fileExists(atPath: bankDirectory.appendingPathComponent($0.fileName).path) }
        guard !present.isEmpty else { throw BackupError.nothingToBackUp }

        let work = fm.temporaryDirectory.appendingPathComponent("VoiceBackup-\(UUID().uuidString)", isDirectory: true)
        let folder = work.appendingPathComponent(folderName(date: date), isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        for (offset, item) in present.enumerated() {
            let source = bankDirectory.appendingPathComponent(item.fileName)
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
            let target = folder.appendingPathComponent(exportName(label: item.label, index: offset + 1, extension: ext))
            try fm.copyItem(at: source, to: target)
        }
        try readme(count: present.count, date: date)
            .write(to: folder.appendingPathComponent("About these recordings.txt"), atomically: true, encoding: .utf8)

        // The system zips a folder when it is read "for uploading" (no third-party code needed).
        // The zipped copy only exists inside the block, so it is copied out.
        let zipURL = work.appendingPathComponent(folder.lastPathComponent + ".zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do { try fm.copyItem(at: zipped, to: zipURL) } catch { copyError = error }
        }
        if coordinationError != nil || copyError != nil || !fm.fileExists(atPath: zipURL.path) {
            throw BackupError.couldNotPack
        }
        try? fm.removeItem(at: folder)
        return zipURL
    }
}
