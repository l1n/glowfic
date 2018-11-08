class CharacterSearcher < Searcher
  attr_reader :templates, :users

  def initialize(search:, templates:)
    @templates = templates
    @users = []
    super(search)
  end

  def search(user_id: nil, params:, page:)
    @search_results = search_users(user_id) if user_id.present?
    @search_results = search_templates(params[:template_id], user_id) if params[:template_id].present? || user_id.present?
    @search_results = search_names(params) if params[:name].present?
    @search_results = @search_results.ordered.paginate(page: page, per_page: 25) unless errors.present?
    @search_results
  end

  private

  def search_users(user_id)
    @users = User.where(id: user_id)
    if @users.present?
      @search_results = @search_results.where(user_id: user_id)
    else
      errors.add(:user, "could not be found.")
      @search_results
    end
  end

  def search_templates(template_id, user_id)
    if template_id.present?
      @templates = Template.where(id: template_id)
      template = @templates.first
      if template.present?
        if @users.present? && template.user_id != @users.first.id
          errors.add(:base, "The specified author and template do not match; template filter will be ignored.")
          @templates = []
          @search_results
        else
          @search_results = @search_results.where(template_id: template_id)
        end
      else
        errors.add(:template, "could not be found.")
        @search_results
      end
    elsif user_id.present?
      @templates = Template.where(user_id: user_id).ordered.limit(25)
      @search_results
    end
  end

  def search_names(params)
    where_calc = []
    where_calc << "name LIKE ?" if params[:search_name].present?
    where_calc << "screenname LIKE ?" if params[:search_screenname].present?
    where_calc << "template_name LIKE ?" if params[:search_nickname].present?

    @search_results.where(where_calc.join(' OR '), *(['%' + params[:name].to_s + '%'] * where_calc.length))
  end
end
