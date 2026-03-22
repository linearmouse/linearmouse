# XCStrings LLM Translation Script

`Scripts/translate-xcstrings.mjs` uses Xcode's native localization export/import flow, then fills unfinished xcstrings entries with an LLM through OpenRouter.

What it does:

- exports `.xcloc` / `.xliff` bundles with `xcodebuild -exportLocalizations`
- inspects only `.xcstrings` translation units inside the exported XLIFF
- skips units whose target is already `translated`
- sends only unfinished units to the model
- imports the translated XLIFF back with `xcodebuild -importLocalizations -mergeImport`

## Install

```bash
npm install
```

## Required environment variables

```bash
export OPENROUTER_API_KEY="your-api-key"
```

Optional:

```bash
export OPENROUTER_MODEL="openai/gpt-4.1-mini"
export OPENROUTER_SITE_URL="https://github.com/linearmouse/linearmouse"
export OPENROUTER_APP_NAME="LinearMouse xcstrings translator"
```

## Usage

Dry run first:

```bash
npm run translate:xcstrings -- --dry-run
```

Translate everything unfinished:

```bash
npm run translate:xcstrings
```

Translate only selected languages:

```bash
npm run translate:xcstrings -- --languages ja,zh-Hans,zh-Hant
```

Use a different model or smaller batches:

```bash
npm run translate:xcstrings -- --model openai/gpt-4.1 --batch-size 5
```

Limit a test run to a few translation units:

```bash
npm run translate:xcstrings -- --max-units 20
```

Keep the exported localization bundle for inspection:

```bash
npm run translate:xcstrings -- --languages ja --keep-export
```

## Notes

- The script uses the OpenAI SDK against OpenRouter's OpenAI-compatible endpoint.
- Extraction and import are handled by Xcode, not by a custom xcstrings parser.
- The script only edits XLIFF units whose `original` file ends with `.xcstrings`; other exported resources are left untouched.
- Xcode's exported XLIFF already expands plural and variation entries into individual `trans-unit` items, so the model works on those units directly.
- Review the diff after each run because model translations can still need terminology cleanup.
