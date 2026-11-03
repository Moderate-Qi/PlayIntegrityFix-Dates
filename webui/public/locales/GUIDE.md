# WebUI Translation Guide

## Add a language

1. Fork [Moderate-Qi/PlayIntegrityFix-Dates](https://github.com/Moderate-Qi/PlayIntegrityFix-Dates).
2. Copy `webui/public/locales/template.xml` into `webui/public/locales/strings/` and name it `{language-code}.xml` using the [Crowdin language codes](https://support.crowdin.com/developer/language-codes).
3. Translate the string values.
4. Add the language to `webui/public/locales/languages.json` in alphabetical order:

```json
{
  "en": "English",
  "fr": "Français",
  "zh-CN": "简体中文"
}
```

5. Add your name to [CONTRIBUTOR.md](CONTRIBUTOR.md) and open a pull request.

## Update a language

Edit the existing XML strings, update the contributor list, and open a pull request.

## Language selection

The WebUI follows the system locale. To choose a language in the browser console:

```javascript
loadTranslations('zh-CN');
```
