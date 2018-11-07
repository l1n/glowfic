class ReplySearcher < Searcher
  def search(user_id: nil, character_id: nil, icon_id: nil, board_id: nil, content: nil, sort: nil, post: nil, template_id: nil, condensed: nil)
    @search_results = @search_results.where(user_id: user_id) if user_id.present?
    @search_results = @search_results.where(character_id: character_id) if character_id.present?
    @search_results = @search_results.where(icon_id: icon_id) if icon_id.present?

    @search_results = search_content(content, sort) if content.present?

    @search_results = search_posts(post, board_id) if post || board_id.present?

    @search_results = search_templates(template_id, user_id) if template_id.present? || user_id.present?

    @search_results = @search_results
      .select('replies.*, characters.name, characters.screenname, users.username')
      .visible_to(current_user)
      .joins(:user)
      .left_outer_joins(:character)
      .with_edit_audit_counts
      .paginate(page: page, per_page: 25)
      .includes(:post)

    unless condensed
      @search_results = @search_results
        .select('icons.keyword, icons.url')
        .left_outer_joins(:icon)
    end
  end

  def search_content(content, sort)
    @search_results = @search_results.search(content).with_pg_search_highlight
    exact_phrases = content.scan(/"([^"]*)"/)
    if exact_phrases.present?
      exact_phrases.each do |phrase|
        phrase = phrase.first.strip
        next if phrase.blank?
        @search_results = @search_results.where("replies.content LIKE ?", "%#{phrase}%")
      end
    end

    append_rank = content.present? ? ', rank DESC' : ''
    if sort == 'created_new'
      @search_results = @search_results.except(:order).order('replies.created_at DESC' + append_rank)
    elsif sort == 'created_old'
      @search_results = @search_results.except(:order).order('replies.created_at ASC' + append_rank)
    elsif content.blank?
      @search_results = @search_results.order('replies.created_at DESC')
    end
  end

  def search_posts(post, board_id)
    if post
      @search_results.where(post_id: post.id)
    elsif board_id.present?
      post_ids = Post.where(board_id: board_id).pluck(:id)
      @search_results.where(post_id: post_ids)
    end
  end

  def search_templates(template_id, user_id)
    if template_id.present?
      @templates = Template.where(id: template_id)
      if @templates.first.present?
        character_ids = Character.where(template_id: @templates.first.id).pluck(:id)
        @search_results = @search_results.where(character_id: character_ids)
      end
    elsif user_id.present?
      @templates = @templates.where(user_id: user_id)
    end
  end
end
