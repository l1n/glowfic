# frozen_string_literal: true
module TagHelper
  def delete_path(tag)
    url_params = {}
    url_params[:page] = page if params[:page].present?
    url_params[:view] = @view if @view.present?
    tag_path(tag, url_params)
  end

  # A tag's name in the reader's interface language when it has been translated into it,
  # falling back to the tag's canonical name. Text that isn't in the page's own language
  # is wrapped in <span lang="…">, so screen readers pronounce it correctly and browsers
  # hyphenate it with the right rules; text that already matches is left as bare text
  # rather than being wrapped in a span that says nothing.
  def localized_tag_name(record)
    localized_span(record.localized_name(reading_languages))
  end

  def localized_tag_description(record)
    record.localized_description(reading_languages)
  end

  def localized_tag_link(record, **opts)
    link_to(localized_tag_name(record), tag_path(record), **opts)
  end

  def localized_tag_text(record)
    record.localized_name.text.to_s
  end

  # The same language-aware link as localized_tag_link, from the [id, name, locale] triple
  # a list that plucks tag columns has instead of a record.
  def localized_tag_column_link(id, name, locale)
    link_to(localized_span(Tag::Localized.new(name, locale)), tag_path(id))
  end

  def localized_span(localized)
    text = localized.text.to_s
    return ''.html_safe if text.blank?
    attributes = localized_attrs(localized)
    return text if attributes.empty?
    tag.span(text, **attributes)
  end

  # lang/dir for a block of localized text, or nothing at all when the text is already in
  # the language the page is being rendered in — an English page doesn't need every string
  # on it stamped lang="en".
  def localized_attrs(localized)
    return {} if Glowfic::Locales.base_code(localized.locale) == Glowfic::Locales.base_code(I18n.locale)
    { lang: localized.locale, dir: (localized.rtl? ? 'rtl' : nil) }.compact
  end

  # Tag types are class names, so the interface can't just titlecase them into English
  # headings and links; these give the translated name for one.
  #
  # They carry the gettext context 'tag type' because the English collides with unrelated
  # wording elsewhere: a Setting tag is a place a story happens, which is not what
  # "Settings" means on the account page, and the two want different words in other
  # languages. The context has to be a literal at each call for xgettext to see it.
  def tag_type_name(type)
    case type
      when 'Setting' then p_('tag type', "Setting")
      when 'Label' then p_('tag type', "Label")
      when 'ContentWarning' then p_('tag type', "Content Warning")
      when 'GalleryGroup' then p_('tag type', "Gallery Group")
      else type.to_s.titlecase
    end
  end

  def tag_type_plural(type)
    case type
      when 'Setting' then p_('tag type', "Settings")
      when 'Label' then p_('tag type', "Labels")
      when 'ContentWarning' then p_('tag type', "Content Warnings")
      when 'GalleryGroup' then p_('tag type', "Gallery Groups")
      else type.to_s.pluralize.titlecase
    end
  end

  def tag_select(obj, form, assoc, opts={})
    attr_name = assoc.to_s.singularize + "_ids"
    preview_collection = instance_variable_get(:"@#{assoc}")

    collection = if preview_collection.nil? # if I used || it would skip []s
      obj.send(assoc) # form.object != obj
    else
      preview_collection
    end
    selected_ids = collection.map(&:id_for_select)

    form.select(
      attr_name,
      options_from_collection_for_select(collection, :id_for_select, :name, selected_ids),
      {},
      { multiple: true }.merge(opts),
    )
  end
end
