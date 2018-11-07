class PostSearcher < Searcher
  def search(board_id: nil, setting_id: nil, subject: nil, completed: false, author_ids: [], character_id: nil)
    @search_results = @search_results.where(board_id: board_id) if board_id.present?
    @search_results = search_settings(setting_id) if setting_id.present?
    @search_results = search_subject(subject) if subject.present?
    @search_results = @search_results.where(status: Post::STATUS_COMPLETE) if completed.present?
    @search_results = search_authors(author_ids) if author_ids.present?
    @search_results = search_characters(character_id) if character_id.present?
  end

  def search_settings(setting_id)
    post_ids = Setting.find(setting_id).post_tags.pluck(:post_id)
    @search_results.where(id: post_ids)
  end

  def search_subjects(subject)
    @search_results.search(subject).where('LOWER(subject) LIKE ?', "%#{subject.downcase}%")
  end

  def search_authors(author_ids)
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
    @search_results.where(id: post_ids.uniq)
  end

  def search_characters
    arel = Post.arel_table
    post_ids = Reply.where(character_id: params[:character_id]).select(:post_id).distinct.pluck(:post_id)
    where = arel[:character_id].eq(params[:character_id]).or(arel[:id].in(post_ids))
    @search_results.where(where)
  end
end
