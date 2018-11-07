class PostSearcher < Searcher
  def search(board_id: nil, setting_id: nil, subject: nil, completed: false, author_ids: [], character_id: nil)
    @search_results = @search_results.where(board_id: params[:board_id]) if params[:board_id].present?
    @search_results = @search_results.where(id: Setting.find(params[:setting_id]).post_tags.pluck(:post_id)) if params[:setting_id].present?
    @search_results = @search_results.search(params[:subject]).where('LOWER(subject) LIKE ?', "%#{params[:subject].downcase}%") if params[:subject].present?
    @search_results = @search_results.where(status: Post::STATUS_COMPLETE) if params[:completed].present?
    if params[:author_id].present?
      post_ids = nil
      params[:author_id].each do |author_id|
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
    if params[:character_id].present?
      arel = Post.arel_table
      post_ids = Reply.where(character_id: params[:character_id]).select(:post_id).distinct.pluck(:post_id)
      where = arel[:character_id].eq(params[:character_id]).or(arel[:id].in(post_ids))
      @search_results = @search_results.where(where)
    end
  end
end
