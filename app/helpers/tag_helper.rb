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
    localized_span(record.localized_name)
  end

  def localized_tag_link(record, **opts)
    link_to(localized_tag_name(record), tag_path(record), **opts)
  end

  def localized_tag_text(record)
    record.localized_name.text.to_s
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
  def tag_type_name(type)
    case type
      when 'Setting' then _("Setting")
      when 'Label' then _("Label")
      when 'ContentWarning' then _("Content Warning")
      when 'GalleryGroup' then _("Gallery Group")
      else type.to_s.titlecase
    end
  end

  def tag_type_plural(type)
    case type
      when 'Setting' then _("Settings")
      when 'Label' then _("Labels")
      when 'ContentWarning' then _("Content Warnings")
      when 'GalleryGroup' then _("Gallery Groups")
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
