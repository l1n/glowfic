module Listable
  extend ActiveSupport::Concern

  included do
    helper_method :posts_from_relation

    attr_reader :unread_ids, :opened_ids
    # unread_ids does not necessarily include fully unread posts
    helper_method :unread_ids, :opened_ids
  end

  def posts_from_relation(relation, no_tests: true, with_pagination: true, select: '')
    posts = relation
      .visible_to(current_user)
      .select('posts.*, boards.name as board_name, users.username as last_user_name'+ select)
      .joins(:board)
      .joins(:last_user)
      .includes(:authors)
      .with_has_content_warnings
      .with_reply_count

    posts = posts.paginate(page: page, per_page: 25) if with_pagination
    posts = posts.no_tests if no_tests

    if logged_in?
      @opened_ids ||= PostView.where(user_id: current_user.id).where('read_at IS NOT NULL').pluck(:post_id)

      opened_posts = PostView.where(user_id: current_user.id).where('read_at IS NOT NULL').where(post_id: posts.map(&:id)).select([:post_id, :read_at])
      @unread_ids ||= []
      @unread_ids += opened_posts.select do |view|
        post = posts.detect { |p| p.id == view.post_id }
        post && view.read_at < post.tagged_at
      end.map(&:post_id)
    end

    posts
  end
end
