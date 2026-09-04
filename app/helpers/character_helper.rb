# frozen_string_literal: true
module CharacterHelper
  # Returns { character_id => [[setting_id, name, locale], …] }.
  #
  # This list plucks columns rather than instantiating tags, so the reader's translation
  # is joined in here instead of being looked up per tag: their name for a setting where
  # one exists, and the setting's own name otherwise. The language comes back with the
  # name so the view can mark it up when it isn't the language of the page.
  def settings_info(characters)
    locale = Glowfic::Locales.base_code(I18n.locale)
    translations = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, locale, locale])
      LEFT JOIN tag_translations
        ON tag_translations.tag_id = tags.id
        AND tag_translations.locale = ?
        AND tags.locale IS DISTINCT FROM ?
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
