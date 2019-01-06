class CharacterSearcher < Searcher
  def initialize(search: Character.unscoped, templates:, users: [])
    super
  end

  def search(user_id: nil, params:, page:)
    search_users(user_id) if user_id.present?
    search_templates(params[:template_id], user_id) if params[:template_id].present? || user_id.present?
    search_names(params) if params[:name].present?
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
    end
  end

  def do_search_templates(template)
    @search_results = @search_results.where(template_id: template.id)
  end

  def search_names(params)
    where_calc = []
    where_calc << "name LIKE ?" if params[:search_name].present?
    where_calc << "screenname LIKE ?" if params[:search_screenname].present?
    where_calc << "template_name LIKE ?" if params[:search_nickname].present?

    @search_results = @search_results.where(where_calc.join(' OR '), *(['%' + params[:name].to_s + '%'] * where_calc.length))
  end
end
