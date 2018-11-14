class ReplySearcher < Searcher
  def initialize(search:, templates:, users:)
    super
  end

  def search(user_id: nil, params:, post: nil, page:)
    @search_results = @search_results.where(user_id: user_id) if user_id.present?
    @search_results = @search_results.where(character_id: params[:character_id]) if params[:character_id].present?
    @search_results = @search_results.where(icon_id: params[:icon_id]) if params[:icon_id].present?
    @search_results = search_content(params[:subj_content]) if params[:subj_content].present?
    @search_resuslts = sort(params[:sort], params[:subject_content]) if params[:sort].present?
    @search_results = search_posts(post, params[:board_id]) if post || params[:board_id].present?
    @search_results = search_templates(params[:template_id], user_id) if params[:template_id].present? || user_id.present?

    @search_results = @search_results
      .select('replies.*, characters.name, characters.screenname, users.username')
      .visible_to(current_user)
      .joins(:user)
      .left_outer_joins(:character)
      .with_edit_audit_counts
      .paginate(page: page, per_page: 25)
      .includes(:post)

    unless params[:condensed]
      @search_results = @search_results
        .select('icons.keyword, icons.url')
        .left_outer_joins(:icon)
    end
    @search_results
  end

  def search_content(content)
    @search_results = @search_results.search(content).with_pg_search_highlight
    exact_phrases = content.scan(/"([^"]*)"/)
    if exact_phrases.present?
      exact_phrases.each do |phrase|
        phrase = phrase.first.strip
        next if phrase.blank?
        @search_results = @search_results.where("replies.content LIKE ?", "%#{phrase}%")
      end
    end
    @search_results
  end

  def sort(sort, content)
    append_rank = content.present? ? ', rank DESC' : ''
    if sort == 'created_new'
      @search_results = @search_results.except(:order).order('replies.created_at DESC' + append_rank)
    elsif sort == 'created_old'
      @search_results = @search_results.except(:order).order('replies.created_at ASC' + append_rank)
    elsif content.blank?
      @search_results = @search_results.order('replies.created_at DESC')
    end
    @search_results
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
      template = Template.find_by(id: template_id)
      if template.present?
        if @users.blank? || template.user_id == @users.first.id
          @templates = [template]
          character_ids = Character.where(template_id: template.id).pluck(:id)
          @search_results.where(character_id: character_ids)
        else
          errors.add(:base, "The specified author and template do not match; template filter will be ignored.")
          @templates = []
        end
      else
        errors.add(:template, "could not be found.")
        @templates = []
      end
    elsif user_id.present?
      @templates = @templates.where(user_id: user_id).ordered.limit(25)
    end
    @search_results
  end
end
