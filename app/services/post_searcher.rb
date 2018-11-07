class PostSearcher < Searcher
  def search(board_id: nil, setting_id: nil, subject: nil, completed: false, author_ids: [], character_id: nil)
    @search_results = @search_results.where(board_id: board_id) if board_id.present?
    @search_results = @search_results.where(id: Setting.find(setting_id).post_tags.pluck(:post_id)) if setting_id.present?
    @search_results = @search_results.search(subject).where('LOWER(subject) LIKE ?', "%#{subject.downcase}%") if subject.present?
    @search_results = @search_results.where(status: Post::STATUS_COMPLETE) if completed.present?
    if author_ids.present?
      post_ids = nil
      author_ids.each do |author_id|
        author_posts = PostAuthor.where(user_id: author_id, joined: true).pluck(:post_id)
        if post_ids.nil?
          post_ids = author_posts
        else
          post_ids &= author_posts
        end
        break if post_ids.empty?
      end
      @search_results = @search_results.where(id: post_ids.uniq)
    end
    if character_id.present?
      arel = Post.arel_table
      post_ids = Reply.where(character_id: character_id).select(:post_id).distinct.pluck(:post_id)
      where = arel[:character_id].eq(character_id).or(arel[:id].in(post_ids))
      @search_results = @search_results.where(where)
    end
  end
end
