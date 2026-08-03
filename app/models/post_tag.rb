# frozen_string_literal: true
class PostTag < ApplicationRecord
  belongs_to :post, inverse_of: :post_tags, optional: false
  belongs_to :tag, inverse_of: :post_tags, optional: true # TODO: This is required, fix bug around validation if it is set as such
  belongs_to :setting, foreign_key: :tag_id, inverse_of: :post_tags, optional: true
  belongs_to :content_warning, foreign_key: :tag_id, inverse_of: :post_tags, optional: true
  belongs_to :label, foreign_key: :tag_id, inverse_of: :post_tags, optional: true

  validates :post, uniqueness: { scope: :tag }
  validates :reveal_after_reply_order, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validate :reveal_threshold_requires_spoiler

  scope :spoilered, -> { where(spoiler: true) }
  scope :unspoilered, -> { where(spoiler: false) }

  # Spoilered taggings are excluded from tag -> post listings entirely, so a
  # spoilered post does not appear under that tag.
  scope :for_reverse_lookup, -> { unspoilered }

  # A nil reveal_after_reply_order means "reveal at the end of the post as it
  # currently stands".
  def revealed_to?(user, read_reply_order: nil)
    return true unless spoiler?
    return false if user.nil?
    return true if post.user_id == user.id
    return true if user.has_permission?(:edit_posts)

    read_order = read_reply_order.nil? ? post.read_reply_order_for(user) : read_reply_order
    return false if read_order.nil?

    threshold = reveal_after_reply_order || post.last_reply_order
    return true if threshold.nil? # no replies yet, so the end is the post itself
    read_order >= threshold
  end

  private

  def reveal_threshold_requires_spoiler
    return if reveal_after_reply_order.nil? || spoiler?
    errors.add(:reveal_after_reply_order, "requires the tagging to be marked as a spoiler")
  end
end
