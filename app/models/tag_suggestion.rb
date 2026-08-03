# frozen_string_literal: true

# A reader proposing a tag on someone else's post. Rejection blocks the tag on
# that post for everyone, not just the original suggester.
class TagSuggestion < ApplicationRecord
  MAX_PENDING_PER_USER = 20
  MAX_PENDING_PER_POST = 10

  belongs_to :post, inverse_of: :tag_suggestions, optional: false
  belongs_to :user, inverse_of: :tag_suggestions, optional: false
  belongs_to :tag, optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  enum :status, { pending: 0, accepted: 1, rejected: 2, endorsed: 3 }

  validates :tag_type, inclusion: { in: Tag::TYPES, allow_nil: true }
  validate :names_exactly_one_tag
  validate :suggester_is_not_the_author, on: :create
  validate :post_accepts_suggestions, on: :create
  validate :within_rate_limits, on: :create

  scope :awaiting_author, -> { pending }
  scope :ordered, -> { order(created_at: :desc) }

  # Deduplication must never reveal a tagging or a rejection the suggester
  # cannot already see: "that tag is already on this post" would expose a hidden
  # spoiler tagging, and "that was already rejected" would expose the author's
  # decision. Any collision the suggester could not observe returns the ordinary
  # confirmation rather than an error.
  #
  # Returns [record_or_nil, outcome].
  def self.submit(post:, user:, tag: nil, tag_type: nil, tag_name: nil, note: nil, spoiler: false, reveal_after_reply_order: nil)
    # A proposed name that already exists is a suggestion of that tag. Without
    # this, re-proposing a rejected tag as a "new" name walks past the block.
    if tag.nil? && tag_type.present? && tag_name.present?
      tag = Tag.where(type: tag_type).find_by(name: tag_name)
      tag_type = tag_name = nil if tag
    end

    existing_tagging = matching_tagging(post: post, tag: tag, tag_type: tag_type, tag_name: tag_name)

    if existing_tagging
      read_order = post.read_reply_order_for(user)
      return [nil, :already_visible] if existing_tagging.revealed_to?(user, read_reply_order: read_order)
      return [endorse(post: post, user: user, tagging: existing_tagging, note: note), :endorsed]
    end

    # Covers a pending duplicate and a standing rejection alike.
    prior = matching_suggestion(post: post, tag: tag, tag_type: tag_type, tag_name: tag_name)
    return [nil, :silently_deduped] if prior

    record = new(
      post: post, user: user, tag: tag, tag_type: tag_type, tag_name: tag_name,
      note: note, spoiler: spoiler, reveal_after_reply_order: reveal_after_reply_order,
    )
    return [record, :invalid] unless record.save

    Notification.notify_user(post.user, :tag_suggested, post: post)
    [record, :created]
  end

  def self.matching_tagging(post:, tag:, tag_type:, tag_name:)
    if tag
      post.post_tags.detect { |post_tag| post_tag.tag_id == tag.id }
    else
      post.post_tags.detect do |post_tag|
        post_tag.tag&.type == tag_type && post_tag.tag&.name&.casecmp?(tag_name.to_s)
      end
    end
  end
  private_class_method :matching_tagging

  def self.matching_suggestion(post:, tag:, tag_type:, tag_name:)
    if tag
      where(post_id: post.id, tag_id: tag.id).first
    else
      where(post_id: post.id, tag_id: nil, tag_type: tag_type, tag_name: tag_name).first
    end
  end
  private_class_method :matching_suggestion

  def self.endorse(post:, user:, tagging:, note:)
    existing = where(post_id: post.id, tag_id: tagging.tag_id).first
    return existing if existing

    create!(
      post: post, user: user, tag_id: tagging.tag_id, note: note,
      status: :endorsed, resolved_at: Time.zone.now,
    )
  end
  private_class_method :endorse

  def tag_display_name
    tag&.name || tag_name
  end

  def tag_display_type
    tag&.type || tag_type
  end

  # Endorsements need no accept or reject action.
  def actionable?
    pending?
  end

  def accept!(resolver:)
    transaction do
      tag_record = tag || Tag.create!(type: tag_type, name: tag_name, user: user)
      PostTag.find_or_create_by!(post: post, tag: tag_record)
      update!(
        status: :accepted, resolved_by: resolver, resolved_at: Time.zone.now,
        tag: tag_record, tag_type: nil, tag_name: nil,
      )
    end
  end

  def reject!(resolver:)
    update!(status: :rejected, resolved_by: resolver, resolved_at: Time.zone.now)
  end

  def allow_again!
    destroy!
  end

  private

  def names_exactly_one_tag
    has_existing = tag_id.present?
    has_proposed = tag_type.present? && tag_name.present?
    return if has_existing ^ has_proposed
    errors.add(:base, "A suggestion must name either an existing tag or a new tag name, not both.")
  end

  def suggester_is_not_the_author
    return if post.nil? || user.nil?
    return unless post.user_id == user.id
    errors.add(:base, "You can tag your own post directly.")
  end

  def post_accepts_suggestions
    return if post.nil?
    return if post.allow_tag_suggestions?
    errors.add(:base, "This author is not accepting tag suggestions.")
  end

  def within_rate_limits
    return if user.nil? || post.nil?

    if TagSuggestion.pending.where(user_id: user.id).count >= MAX_PENDING_PER_USER
      errors.add(:base, "You have too many suggestions awaiting a response.")
    end

    return unless TagSuggestion.pending.where(post_id: post.id).count >= MAX_PENDING_PER_POST
    errors.add(:base, "This post already has as many pending suggestions as it can hold.")
  end
end
