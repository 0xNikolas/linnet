import Testing
import Foundation
@testable import LinnetLibrary

@Test func audioFileExtensionsFilter() async {
    let scanner = FolderScanner()
    let mp3 = await scanner.isAudioFile(URL(filePath: "/test.mp3"))
    let flac = await scanner.isAudioFile(URL(filePath: "/test.flac"))
    let m4a = await scanner.isAudioFile(URL(filePath: "/test.m4a"))
    let txt = await scanner.isAudioFile(URL(filePath: "/test.txt"))
    let jpg = await scanner.isAudioFile(URL(filePath: "/test.jpg"))

    #expect(mp3 == true)
    #expect(flac == true)
    #expect(m4a == true)
    #expect(txt == false)
    #expect(jpg == false)
}

@Test func audioExtensionsCaseInsensitive() async {
    let scanner = FolderScanner()
    let upper = await scanner.isAudioFile(URL(filePath: "/test.MP3"))
    let mixed = await scanner.isAudioFile(URL(filePath: "/test.FlAc"))
    #expect(upper == true)
    #expect(mixed == true)
}
