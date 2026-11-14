# Contributing to Soaro

Thank you for your interest. Bug reports, ideas, translations and code are all welcome.

Soaro is a small project made by one person, so please be patient. I will answer as soon as I can.

## Report a bug or suggest something

Open an [issue](https://github.com/sebmafate/soaro/issues). For a bug, please give:

- your macOS version and Mac model
- the Soaro version (in the Finder, select Soaro.app and press Cmd-I)
- what you did, what you expected, and what happened
- the output of `Soaro --diagnostics` if it is about a measurement. It contains your computer name and process list, so read it and remove what you do not want to share

For a security problem, **do not open a public issue**. Read [SECURITY.md](SECURITY.md).

## Translations

The texts of the app are in two String Catalogs:

- `Sources/Soaro/Resources/Localizable.xcstrings`: the interface
- `Sources/Soaro/Resources/InfoPlist.xcstrings`: the permission text shown by macOS

The keys are the English texts. The languages are English (source), French, German, Spanish, Italian, Brazilian Portuguese, Japanese, Simplified Chinese and Korean.

**To fix a translation:** open the `.xcstrings` file in Xcode, which shows a table by language. You can also edit the JSON by hand. Then run the tests and open a pull request.

**To add a language:** add its code (for example `nl`) to every entry. Xcode can do it with the "+" button of the catalog. Then check the layout, because some languages are longer.

Please follow these rules:

- Keep the placeholders: `%@`, `%lld`, `%1$@`... If the word order changes, number **all** the placeholders of that string (`%2$lld ... %1$@`).
- Keep `%%` for a literal percent sign and keep line breaks (`\n`).
- Do not translate *Soaro*, *macOS*, *Wi-Fi*, *VPN*, *CPU*, *GPU*, *SMART*, or file names and commands.
- Use Apple's own words for macOS features (Finder, System Settings, Time Machine, Trash...), as they appear in macOS in your language.
- Be short. Menu bar items and small cards have little space.
- Tone: calm and direct. No exclamation marks, no emoji.

The seven non-English, non-French translations were made with AI help. A review by a native speaker is the most useful contribution you can make.

## Code

```bash
swift test                        # run the tests
swift run                         # run the app in development
scripts/build-app.sh              # build build/Soaro.app
```

Please:

- keep changes small and focused. One pull request, one subject
- add or update a test when you change behavior. Pure logic (`RecommendationEngine`, `Advice`, `Format`...) is easy to test
- run `swift test` before you open the pull request
- never write an action that deletes something without a confirmation, and keep the "home folder only" rule (`CleanupService.isSafeToDelete`)
- never make the app change a macOS setting. Soaro suggests, it does not decide
- write user-visible texts in English, with `String(localized:)` or `LocalizedStringKey`

By contributing, you agree that your work is released under the [GPL-3.0](LICENSE).

## Questions

Open an issue or a discussion. There is no wrong question.
