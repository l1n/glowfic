# frozen_string_literal: true

# The interface is translated with gettext rather than Rails' YAML locale files, so
# that translators can work with ordinary .po files in the tools they already use.
#
# Translations are read straight out of locale/<code>/glowfic.po; there is no compile
# step, so contributing a language is "add one file" rather than "add a file and commit
# a generated binary alongside it". See doc/TRANSLATING.md.
#
# The `gettext` gem (development only) provides the `rake gettext:find` / `gettext:pack`
# tooling that regenerates locale/glowfic.pot from the source; reading .po at runtime
# only needs fast_gettext, which ships its own parser.
FastGettext.add_text_domain(
  'glowfic',
  path: Rails.root.join('locale').to_s,
  type: :po,
  ignore_fuzzy: true,
  report_warning: false,
)
FastGettext.default_text_domain = 'glowfic'
FastGettext.default_available_locales = Glowfic::Locales.ui_codes
FastGettext.default_locale = Glowfic::Locales::DEFAULT
