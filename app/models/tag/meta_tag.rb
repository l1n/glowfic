# frozen_string_literal: true
class Tag::MetaTag < ApplicationRecord
  self.table_name = 'tag_tags'

  belongs_to :child_tag, class_name: 'Tag', foreign_key: :tagged_id, inverse_of: :child_meta_tags, optional: true
  belongs_to :parent_tag, class_name: 'Tag', foreign_key: :tag_id, inverse_of: :parent_meta_tags, optional: true
  belongs_to :child_setting, class_name: 'Setting', foreign_key: :tagged_id, inverse_of: :child_setting_tags, optional: true
  belongs_to :parent_setting, class_name: 'Setting', foreign_key: :tag_id, inverse_of: :parent_setting_tags, optional: true

  scope :confirmed, -> { where(suggested: false) }
  scope :suggested, -> { where(suggested: true) }

  validates :child_tag, uniqueness: { scope: :parent_tag }
  validate :tags_share_a_type
  validate :edge_does_not_close_a_cycle

  def self.ancestor_ids_of(tag)
    walk_ids(tag, start_column: :tagged_id, next_column: :tag_id)
  end

  def self.descendant_ids_of(tag)
    walk_ids(tag, start_column: :tag_id, next_column: :tagged_id)
  end

  # Cycle-safe: rows predating the cycle validation, or created by an import,
  # must not be able to hang the traversal.
  def self.walk_ids(tag, start_column:, next_column:)
    return [] if tag.nil? || tag.id.nil?

    id = connection.quote(tag.id)
    sql = <<~SQL.squish
      WITH RECURSIVE walk(id, path, cycle) AS (
        SELECT #{id}::integer, ARRAY[#{id}::integer], false
        UNION ALL
        SELECT tag_tags.#{next_column}, walk.path || tag_tags.#{next_column}, tag_tags.#{next_column} = ANY(walk.path)
        FROM tag_tags
        JOIN walk ON tag_tags.#{start_column} = walk.id
        WHERE NOT walk.cycle AND tag_tags.suggested = false
      )
      SELECT DISTINCT id FROM walk WHERE id != #{id}
    SQL

    connection.select_values(sql).map(&:to_i)
  end
  private_class_method :walk_ids

  private

  def tags_share_a_type
    return if child_tag.nil? || parent_tag.nil?
    return if child_tag.type == parent_tag.type
    errors.add(:base, "Implications can only connect tags of the same type.")
  end

  def edge_does_not_close_a_cycle
    return if child_tag.nil? || parent_tag.nil?

    if child_tag == parent_tag
      errors.add(:base, "A tag cannot imply itself.")
      return
    end

    return unless Tag::MetaTag.ancestor_ids_of(parent_tag).include?(child_tag.id)
    errors.add(
      :base,
      "#{parent_tag.name} already implies #{child_tag.name}, directly or indirectly, so this would create a loop.",
    )
  end
end
