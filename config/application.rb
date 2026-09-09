# frozen_string_literal: true
require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Middleware referenced from `config.middleware.use` below has to be loaded
# before the application config block runs, since Zeitwerk autoload isn't
# set up yet at that point and `MiddlewareStack#use` doesn't const-resolve.
require_relative '../app/middleware/anon_load_shed'

module Glowfic
  ALLOWED_TAGS = %w(b i u sub sup del ins hr p br div span pre code h1 h2 h3 h4 h5 h6 ul ol li dl dt dd a img blockquote q table tbody td th thead tr
                    strike s strong em big small font cite abbr var samp kbd mark ruby rp rt bdo wbr details summary)
  ALLOWED_ATTRIBUTES = {
    :all         => %w(xml:lang class style title lang dir),
    "hr"         => %w(width),
    "li"         => %w(value),
    "ol"         => %w(reversed start type),
    "a"          => %w(href hreflang rel target type),
    "del"        => %w(cite datetime),
    "table"      => %w(width),
    "td"         => %w(abbr width colspan rowspan),
    "th"         => %w(abbr width colspan rowspan),
    "blockquote" => %w(cite),
    "cite"       => %w(href),
  }

  DISCORD_LINK_CONSTELLATION = 'https://discord.gg/RWUPXQD'

  # Languages the site knows about, as BCP 47 primary subtags mapped to their
  # endonyms (the name of the language in that language). Used for three things:
  #   - the UI language a user can pick (restricted to LANGUAGES with a locale/*.po)
  #   - the default language a user writes content in
  #   - the language dropdown in the editor and the tag translation editor
  # Add a language here and drop a locale/<code>/glowfic.po beside it to make it
  # selectable; see doc/TRANSLATING.md.
  module Locales
    DEFAULT = 'en'

    LANGUAGES = {
      'ar' => 'العربية',
      'cs' => 'Čeština',
      'da' => 'Dansk',
      'de' => 'Deutsch',
      'el' => 'Ελληνικά',
      'en' => 'English',
      'eo' => 'Esperanto',
      'es' => 'Español',
      'fa' => 'فارسی',
      'fi' => 'Suomi',
      'fr' => 'Français',
      'he' => 'עברית',
      'hi' => 'हिन्दी',
      'hu' => 'Magyar',
      'id' => 'Bahasa Indonesia',
      'it' => 'Italiano',
      'ja' => '日本語',
      'ko' => '한국어',
      'nl' => 'Nederlands',
      'no' => 'Norsk',
      'pl' => 'Polski',
      'pt' => 'Português',
      'ro' => 'Română',
      'ru' => 'Русский',
      'sv' => 'Svenska',
      'tr' => 'Türkçe',
      'uk' => 'Українська',
      'vi' => 'Tiếng Việt',
      'zh' => '中文',
    }.freeze

    CODES = LANGUAGES.keys.freeze

    # Languages written right-to-left, so content tagged with them also gets dir="rtl".
    RTL_CODES = %w(ar fa he ur).freeze

    # A conservative BCP 47 subset: a primary subtag plus optional script/region
    # subtags, e.g. "es", "pt-BR", "zh-Hant", "zh-Hant-HK". Deliberately narrower
    # than the full grammar, since this gates what users may put in a lang="".
    TAG_FORMAT = /\A[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?\z/

    class << self
      # The subset of LANGUAGES the interface has actually been translated into.
      # English is always available since it is the language the source is written in.
      def ui_codes
        @ui_codes ||= ([DEFAULT] + translated_codes).uniq.sort
      end

      def ui_options
        ui_codes.map { |code| [LANGUAGES.fetch(code, code), code] }
      end

      # Every language content may be tagged as, whether or not the UI is translated.
      def content_options
        LANGUAGES.map { |code, name| [name, code] }
      end

      def name_for(code)
        LANGUAGES[base_code(code)] || code
      end

      def rtl?(code)
        RTL_CODES.include?(base_code(code))
      end

      def valid_tag?(code)
        code.is_a?(String) && code.match?(TAG_FORMAT)
      end

      # "pt-BR" -> "pt". Nil-safe so callers can pass a user's unset setting.
      def base_code(code)
        code.to_s.split('-').first.presence
      end

      def reset_cache!
        @ui_codes = nil
      end

      private

      def translated_codes
        Rails.root.glob('locale/*/glowfic.po').map { |path| path.dirname.basename.to_s } & CODES
      end
    end
  end

  module Sanitizers
    DIRECTIONS = %w(ltr rtl auto).freeze

    # `lang`, `xml:lang` and `dir` are allowed on every element so authors can mark up
    # passages in another language (<span lang="es">). Sanitize only filters attribute
    # names, not values, so this drops values that aren't well-formed language tags or
    # real directions instead of echoing arbitrary user strings into the page.
    LANGUAGE_TRANSFORMER = lambda do |env|
      node = env[:node]
      next unless node.element?

      ['lang', 'xml:lang'].each do |attribute|
        value = node[attribute]
        node.remove_attribute(attribute) if value && !Locales.valid_tag?(value)
      end

      direction = node['dir']
      node.remove_attribute('dir') if direction && DIRECTIONS.exclude?(direction.downcase)

      nil
    end

    WRITTEN_CONF = Sanitize::Config.merge(
      Sanitize::Config::RELAXED,
      elements: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRIBUTES,
      transformers: [LANGUAGE_TRANSFORMER],
    )

    def self.written(text)
      Sanitize.fragment(text, WRITTEN_CONF).html_safe # rubocop:disable Rails/OutputSafety
    end

    DESCRIPTION_CONF = Sanitize::Config.merge(
      Sanitize::Config::RELAXED,
      elements: ['a'],
      attributes: { 'a' => ['href'] },
    )

    def self.description(text)
      Sanitize.fragment(text, DESCRIPTION_CONF).html_safe # rubocop:disable Rails/OutputSafety
    end

    def self.full(text)
      Sanitize.fragment(text).html_safe # rubocop:disable Rails/OutputSafety
    end
  end

  # Configuration for the application, engines, and railties goes here.
  #
  # These settings can be overridden in specific environments using the files
  # in config/environments, which are processed later.
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # use newer 7.1 cache format
    config.active_support.cache_format_version = 7.1

    # Opt into the Rails 8.1 behaviour now to silence the deprecation warning;
    # `to_time` keeps the receiver's full timezone rather than just its offset.
    config.active_support.to_time_preserves_timezone = :zone

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = 'Eastern Time (US & Canada)'
    # config.eager_load_paths << Rails.root.join("extras")

    config.action_view.sanitized_allowed_tags = Glowfic::ALLOWED_TAGS
    config.action_view.sanitized_allowed_attributes = %w(href src width height alt cite datetime title class name xml:lang abbr style target)
    config.middleware.use Rack::Pratchett
    config.middleware.use Rack::Deflater
    # Sheds anonymous traffic with deep queue wait so logged-in users keep
    # getting served during saturation. See app/middleware/anon_load_shed.rb.
    config.middleware.use AnonLoadShed

    # Setting enables YJIT as of Ruby 3.3, to bring sizeable performance improvements. We are
    # deploying to a memory constrained environment so we set this to `false`.
    config.yjit = false

    # reduce memory use of strings in ActionView Templates
    # https://guides.rubyonrails.org/configuring.html#config-action-view-frozen-string-literal
    config.action_view.frozen_string_literal = true
  end
end
