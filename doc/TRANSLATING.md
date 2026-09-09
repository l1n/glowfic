# Translating the Constellation

The site's own text — buttons, labels, headings, flash messages — is translated with
[gettext](https://www.gnu.org/software/gettext/). Translations live in ordinary `.po`
files under `locale/`, so you can work on them in Poedit, Weblate, Lokalize, or a plain
text editor, and contribute one by opening a pull request that adds or edits a single file.

This is separate from the language a *post* is written in. Marking a passage of writing as
being in another language is done in the editor with the Language control; see
"Content languages" below.

## Layout

```
locale/
  glowfic.pot          # the template: every translatable string in the source
  es/
    glowfic.po         # the Spanish translation
  fr/
    glowfic.po         # …and so on, one directory per language
```

There is no `locale/en/`: English is the language the source is written in, so the msgids
*are* the English text.

The `.po` files are read directly at runtime. You do not need to compile them to `.mo`, and
you should not commit compiled files.

## Adding a language

1. Check that the language is listed in `Glowfic::Locales::LANGUAGES` in
   `config/application.rb`. If it isn't, add it — the key is the
   [BCP 47](https://www.w3.org/International/articles/language-tags/) subtag (`es`, `ja`,
   `pt-BR`), and the value is the language's name *in that language* (`Español`, not
   `Spanish`), since that's how it's shown in the language picker.
2. Create the file:

   ```
   bin-docker/rake gettext:add_language[es]
   ```

   or copy `locale/glowfic.pot` to `locale/es/glowfic.po` by hand and fill in the header.
3. Translate the entries and open a pull request. A partial translation is fine and useful:
   anything you leave untranslated falls back to English rather than breaking.

Once a `locale/<code>/glowfic.po` exists, that language appears in the "Interface language"
dropdown in account settings automatically — nothing else needs to be registered.

## Updating an existing translation

When the source text changes, regenerate the template and merge it into each language:

```
bin-docker/rake gettext:find
```

This rewrites `locale/glowfic.pot` from the source and merges the new strings into every
`locale/*/glowfic.po`, marking changed entries `#, fuzzy`. Fuzzy entries are ignored at
runtime (the English is shown instead) until a translator confirms them, so it's safe to
commit the merge before the translations catch up.

## The long-form pages

The terms of service, privacy policy and DMCA policy are documents, not interfaces. They
are not in the `.po` files, and deliberately so: split into several hundred sentence
fragments they can't be translated into something coherent, let alone something that still
means what the English means.

Translate them as whole pages instead. Rails picks a template by locale automatically, so
adding

```
app/views/about/tos.es.haml
```

is all that's needed — readers whose interface language is Spanish get that page, everyone
else keeps `tos.haml`. The same works for `privacy`, `dmca` and `contact`.

Because these carry legal weight, a translation of one should say, at the top, that the
English version is the one that governs, and it should be reviewed by someone who is
comfortable with both languages and the subject matter.

## What translators should know

- `%{name}`-style placeholders and `%s`/`%d` must survive into the translation; the text
  around them can move freely.
- Entries with `msgid_plural` need one form per `nplurals` in your header's `Plural-Forms`.
- Entries are sorted by msgid and carry no source references, which keeps diffs readable
  when the template is regenerated. Comments starting with `#.` are notes from developers;
  if a string's context still isn't clear, `git grep` for the English text, or ask on the
  pull request.
- If a string is ambiguous or impossible to translate well, say so on the pull request —
  the fix is usually to reword or split the English.

## For developers

Wrap user-facing strings in `_()`, and plurals in `n_()`:

```ruby
_("Save")
n_("%{count} reply", "%{count} replies", count) % { count: count }
```

`_()` is available everywhere (views, helpers, models, controllers) — gettext_i18n_rails
mixes it into `Object`.

Prefer complete sentences over concatenated fragments: word order differs between
languages, so `_("Deleted %{name}") % { name: … }` translates and `_("Deleted ") + name`
does not.

Run `bundle exec rake gettext:find` after adding strings, and commit the updated
`locale/glowfic.pot` alongside your change.

## Content languages

Marking up *writing* — a line of Spanish dialogue in an English post — is a separate
feature and needs no translation files.

- Each user has a **writing language** in account settings, which the editor's language
  controls start from, and an ordered list of **languages they read**. Tag names are shown
  in the first of those with a translation; the editor's language menu lists them in that
  order; and with the interface language on Automatic, the site itself is shown in the
  first of them that has a `.po` file.
- The Rich Text editor has a **Language** menu in its toolbar; the HTML and Markdown
  editors have a **Language / Wrap selection** bar above the text area. Both wrap the
  selected text in `<span lang="…">`.
- `lang`, `xml:lang` and `dir` are allowed on every element the sanitizer permits, and
  their values are checked against the BCP 47 subset in `Glowfic::Locales::TAG_FORMAT`.
- Tags (settings, labels, content warnings, gallery groups) can carry a name and
  description per language, edited on the tag's own edit page. Readers see the name in
  their interface language when one exists, and the tag's original name otherwise.
