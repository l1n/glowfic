# frozen_string_literal: true
class TagTranslation < ApplicationRecord
  belongs_to :tag, inverse_of: :tag_translations, optional: false

  validates :locale,
    presence: true,
    inclusion: { in: Glowfic::Locales::CODES, allow_blank: true },
    uniqueness: { scope: :tag_id, allow_blank: true }
  validates :name, presence: true, length: { maximum: 255 }

  scope :ordered, -> { order(locale: :asc) }

  nilify_blanks

  # The name of this translation's language, in that language ("Español").
  def language_name
    Glowfic::Locales.name_for(locale)
  end

  def rtl?
    Glowfic::Locales.rtl?(locale)
  end
end
