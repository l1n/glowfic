# frozen_string_literal: true
module CharacterHelper
  # Returns { character_id => [[setting_id, name, locale], …] }.
  #
  # This list plucks columns rather than instantiating tags, so the reader's translation
  # is joined in here instead of being looked up per tag: their name for a setting where
  # one exists, and the setting's own name otherwise. The language comes back with the
  # name so the view can mark it up when it isn't the language of the page.
  def settings_info(characters)
    # The reader's languages, best first; each region-specific code also tries its bare
    # language, mirroring Tag#translation_for. A setting already written in one of these
    # languages keeps its own name rather than taking a lower-ranked translation.
    languages = reading_languages.flat_map { |code| [code, Glowfic::Locales.base_code(code)] }.compact.uniq
    languages_literal = "ARRAY[#{languages.map { |code| ActiveRecord::Base.connection.quote(code) }.join(', ')}]::varchar[]"
    translations = <<~SQL.squish
      LEFT JOIN LATERAL (
        SELECT tag_translations.name, tag_translations.locale
        FROM tag_translations
        WHERE tag_translations.tag_id = tags.id
          AND tag_translations.locale = ANY(#{languages_literal})
          AND (tags.locale IS NULL OR array_position(#{languages_literal}, tags.locale::varchar) IS NULL
               OR array_position(#{languages_literal}, tags.locale::varchar) > array_position(#{languages_literal}, tag_translations.locale::varchar))
        ORDER BY array_position(#{languages_literal}, tag_translations.locale::varchar)
        LIMIT 1
      ) tag_translations ON true
    SQL
    columns = Arel.sql(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, Glowfic::Locales::DEFAULT]))
      ARRAY_AGG(tags.id ORDER BY character_tags.id ASC) AS setting_ids,
      ARRAY_AGG(COALESCE(tag_translations.name, tags.name) ORDER BY character_tags.id ASC),
      ARRAY_AGG(COALESCE(tag_translations.locale, tags.locale, ?) ORDER BY character_tags.id ASC)
    SQL

    settings = characters.joins(:settings).joins(translations).group(:id)
    settings.pluck(:id, columns).to_h { |id, ids, names, locales| [id, ids.zip(names, locales)] }
  end

  def characters_list(characters, show_template)
    characters = characters.left_outer_joins(:template) if show_template
    attributes = [:id, :name, :nickname, :screenname, :pb, :cluster, :user_id, 'users.username', Arel.sql('users.deleted as user_deleted')]
    attributes += ['templates.id', 'templates.name'] if show_template
    characters.joins(:user).pluck(*attributes)
  end

  def character_menu_link(link_params)
    link_params = params.permit(:character_split, :retired, :view).to_h.merge(link_params)
    url_for(**link_params.symbolize_keys)
  end
end
