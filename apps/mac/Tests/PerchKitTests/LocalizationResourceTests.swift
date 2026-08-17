import Foundation
import Testing

@Suite("Localization resources")
struct LocalizationResourceTests {
    @Test func permissionActionsExistInEachSupportedLanguage() throws {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = appRoot.appendingPathComponent("Resources")

        let english = try String(
            contentsOf: resources.appendingPathComponent("en.lproj/Localizable.strings"),
            encoding: .utf8)
        let french = try String(
            contentsOf: resources.appendingPathComponent("fr.lproj/Localizable.strings"),
            encoding: .utf8)

        let englishEntries = [
            "\"This chat\" = \"This chat\";",
            "\"Allow all %lld\" = \"Allow all %lld\";",
            "\"Deny all\" = \"Deny all\";",
            "\"Ask in terminal\" = \"Ask in terminal\";",
            "\"Allows %@ for the rest of this conversation\" = \"Allows %@ for the rest of this conversation\";",
            "\"Adds %@ to this project's .claude/settings.local.json\" = \"Adds %@ to this project's .claude/settings.local.json\";",
        ]
        let frenchEntries = [
            "\"This chat\" = \"Ce chat\";",
            "\"Allow all %lld\" = \"Tout autoriser (%lld)\";",
            "\"Deny all\" = \"Tout refuser\";",
            "\"Ask in terminal\" = \"Dans le terminal\";",
            "\"Allows %@ for the rest of this conversation\" = \"Autorise %@ pour le reste de cette conversation\";",
            "\"Adds %@ to this project's .claude/settings.local.json\" = \"Ajoute %@ au fichier .claude/settings.local.json de ce projet\";",
        ]

        for entry in englishEntries { #expect(english.contains(entry)) }
        for entry in frenchEntries { #expect(french.contains(entry)) }
    }
}
