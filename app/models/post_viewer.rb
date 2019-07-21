class PostViewer < ApplicationRecord
  belongs_to :post, optional: false
  belongs_to :user, optional: false

  after_commit :invalidate_cache

  CACHE_VERSION = 1

  def self.cache_string_for(user)
    "#{Rails.env}.#{CACHE_VERSION}.visible_posts.#{user.id}"
  end

  private

  def invalidate_cache
    Rails.cache.delete(PostViewer.cache_string_for(self.user.id))
  end
end
