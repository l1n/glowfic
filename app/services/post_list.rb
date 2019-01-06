class PostList
  extend ActiveModel::Translation
  extend ActiveModel::Validations

  attr_reader :errors, :posts, :opened_ids, :unread_ids

  def initialize(relation, no_tests: true, with_pagination: true, select: '', user: nil)
    @no_tests = no_tests
    @pagination = with_pagination
    @select = select
    @errors = ActiveModel::Errors.new(self)
    @user = user
    @posts = expand_posts(relation)
    format_posts
  end

  def format_posts
    @posts = @posts.paginate(page: page, per_page: 25) if @with_pagination
    @posts = @posts.no_tests if @no_tests

    if @user.present?
      @opened_ids ||= PostView.where(user_id: @user.id).where('read_at IS NOT NULL').pluck(:post_id)

      opened_posts = PostView.where(user_id: @user.id).where('read_at IS NOT NULL').where(post_id: @posts.map(&:id)).select([:post_id, :read_at])
      @unread_ids ||= []
      @unread_ids += opened_posts.select do |view|
        post = @posts.detect { |p| p.id == view.post_id }
        post && view.read_at < post.tagged_at
      end.map(&:post_id)
    end
  end

  private

  def expand_posts(relation)
    posts = relation
      .select('posts.*, boards.name as board_name, users.username as last_user_name'+ @select)
      .joins(:board)
      .joins(:last_user)
      .includes(:authors)
      .with_has_content_warnings
      .with_reply_count

    visible_to(posts, @user)
  end

  def visible_to(posts, user=nil)
    if user
      posts.where(privacy: Concealable::PUBLIC)
        .or(posts.where(privacy: Concealable::REGISTERED))
        .or(posts.where(privacy: Concealable::ACCESS_LIST, user_id: user.id))
        .or(posts.where(privacy: Concealable::ACCESS_LIST, id: PostViewer.where(user_id: user.id).select(:post_id)))
        .or(posts.where(privacy: Concealable::PRIVATE, user_id: user.id))
    else
      posts.where(privacy: Concealable::PUBLIC)
    end
  end
end
