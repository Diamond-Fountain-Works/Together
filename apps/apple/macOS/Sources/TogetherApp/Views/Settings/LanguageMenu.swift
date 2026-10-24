import SwiftUI
import TogetherCore

struct LanguageMenu: View {
    @ObservedObject private var settings = LanguageSettings.shared

    var body: some View {
        Menu {
            Picker(Copy.text("language.title"), selection: $settings.language) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(Copy.text("language.option." + language.rawValue)).tag(language)
                }
            }
        } label: {
            Image(systemName: TogetherSymbols.name("globe")).font(.system(size: 18)).frame(width: 32, height: 30)
        }
        .togetherBorderlessMenu().togetherHideMenuIndicator().fixedSize()
        .accessibilityLabel(Copy.text("language.title"))
        .accessibilityIdentifier("settings.language")
        .help(Copy.text("language.title"))
    }
}
