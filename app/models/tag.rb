# frozen_string_literal: true
class Tag < ApplicationRecord
  belongs_to :user, optional: false
  has_many :user_tags, dependent: :destroy, inverse_of: :tag
  has_many :users, through: :user_tags, dependent: :destroy
  has_many :post_tags, dependent: :destroy, inverse_of: :tag
  has_many :posts, through: :post_tags, dependent: :destroy
  has_many :character_tags, dependent: :destroy, inverse_of: :tag
  has_many :characters, through: :character_tags, dependent: :destroy
  has_many :gallery_tags, dependent: :destroy, inverse_of: :tag
  has_many :galleries, through: :gallery_tags, dependent: :destroy
  has_many :tag_translations, -> { ordered }, dependent: :destroy, inverse_of: :tag

  TYPES = %w(Setting Label ContentWarning GalleryGroup)

  validates :name, :type, presence: true
  validates :name, uniqueness: { scope: :type }
  validates :locale, inclusion: { in: Glowfic::Locales::CODES }, allow_nil: true

  accepts_nested_attributes_for :tag_translations, allow_destroy: true, reject_if: :blank_translation?

  scope :ordered_by_type, -> { order(type: :desc, name: :asc) }

  scope :ordered_by_name, -> { order(name: :asc) }

  scope :ordered_by_id, -> { order(id: :asc) }

  scope :ordered_by_user_tag, -> { order('user_tags.id ASC') }

  scope :ordered_by_char_tag, -> { order('character_tags.id ASC') }

  scope :ordered_by_gallery_tag, -> { order('gallery_tags.id ASC') }

  scope :ordered_by_post_tag, -> { order('post_tags.id ASC') }

  scope :ordered_by_tag_tag, -> { order('tag_tags.id ASC') }

  scope :with_character_counts, -> {
    select("(SELECT COUNT(DISTINCT character_tags.character_id) FROM character_tags WHERE character_tags.tag_id = tags.id) AS character_count")
  }

  def editable_by?(user)
    return false unless user
    return true if deletable_by?(user)
    return true if user.has_permission?(:edit_tags)
    return false if user.read_only?
    return false unless is_a?(Setting)
    !owned?
  end

  def deletable_by?(user)
    return false unless user
    return true if user.has_permission?(:delete_tags)
    user.id == user_id
  end

  def as_json(options={})
    tag_json = { id: self.id, text: self.name }
    return tag_json unless options[:include].present? && options[:include].include?(:gallery_ids)

    g_tags = gallery_tags.joins(:gallery)
    g_tags = g_tags.where(galleries: { user_id: options[:user_id] }) if options[:user_id].present?
    tag_json[:gallery_ids] = g_tags.pluck(:gallery_id).sort
    tag_json
  end

  # Name and description in the requested language, falling back to the canonical
  # copy stored on the tag itself. The language the text is *actually* in comes back
  # alongside it, so callers can mark it up with lang="" when it isn't the one the
  # reader asked for. A tag with no translations behaves exactly as it always has.
  Localized = Struct.new(:text, :locale) do
    def rtl?
      Glowfic::Locales.rtl?(locale)
    end
  end

  # The language the canonical name/description are written in.
  def source_locale
    locale.presence || Glowfic::Locales::DEFAULT
  end

  # `targets` is one language or an ordered list of them (a reader's preferences, best
  # first); the first with a translation wins.
  def localized_name(targets=I18n.locale)
    translation = translation_for(targets)
    return Localized.new(name, source_locale) if translation.nil?
    Localized.new(translation.name, translation.locale)
  end

  def localized_description(targets=I18n.locale)
    translation = translation_for(targets)
    return Localized.new(description, source_locale) if translation.nil? || translation.description.blank?
    Localized.new(translation.description, translation.locale)
  end

  # Walks the targets in order. For each, an exact match ("pt-BR") beats the bare language
  # ("pt"), so a region-specific translation wins for readers who asked for that region.
  # Reaching a target the tag is already written in stops the search: the canonical text
  # is that reader's preference, and no lower-ranked translation should displace it.
  def translation_for(targets)
    by_locale = tag_translations.index_by(&:locale)
    Array(targets).each do |target|
      codes = [target.to_s.presence, Glowfic::Locales.base_code(target)].compact.uniq
      return nil if codes.include?(source_locale)
      found = codes.filter_map { |code| by_locale[code] }.first
      return found if found
    end
    nil
  end

  def translated_locales
    tag_translations.map(&:locale)
  end

  def id_for_select
    return id if persisted? # id present on unpersisted records when associated record is invalid
    "_#{name}"
  end

  def user_count
    return read_attribute(:user_count) if has_attribute?(:user_count)
    users.count
  end

  def post_count
    return read_attribute(:post_count) if has_attribute?(:post_count)
    posts.count
  end

  def character_count
    return read_attribute(:character_count) if has_attribute?(:character_count)
    characters.count
  end

  def merge_with(other_tag)
    transaction do
      # rubocop:disable Rails/SkipsModelValidations
      UserTag.where(tag_id: other_tag.id).where(user_id: user_tags.select(:user_id).distinct.pluck(:user_id)).delete_all
      UserTag.where(tag_id: other_tag.id).update_all(tag_id: self.id)
      PostTag.where(tag_id: other_tag.id).where(post_id: post_tags.select(:post_id).distinct.pluck(:post_id)).delete_all
      PostTag.where(tag_id: other_tag.id).update_all(tag_id: self.id)
      CharacterTag.where(tag_id: other_tag.id).where(character_id: character_tags.select(:character_id).distinct.pluck(:character_id)).delete_all
      CharacterTag.where(tag_id: other_tag.id).update_all(tag_id: self.id)
      GalleryTag.where(tag_id: other_tag.id).where(gallery_id: gallery_tags.select(:gallery_id).distinct.pluck(:gallery_id)).delete_all
      GalleryTag.where(tag_id: other_tag.id).update_all(tag_id: self.id)
      Tag::SettingTag.where(tag_id: other_tag.id, tagged_id: self.id).delete_all
      Tag::SettingTag.where(tag_id: self.id, tagged_id: other_tag.id).delete_all
      Tag::SettingTag.where(tag_id: other_tag.id).update_all(tag_id: self.id)
      Tag::SettingTag.where(tagged_id: other_tag.id).update_all(tagged_id: self.id)
      other_tag.destroy
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  private

  def blank_translation?(attributes)
    attributes = attributes.with_indifferent_access if attributes.respond_to?(:with_indifferent_access)
    attributes[:locale].blank? || attributes[:name].blank?
  end
end
