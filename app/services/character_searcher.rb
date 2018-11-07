class CharacterSearcher < Searcher
  def search(user_id: nil, template_id: nil, name: nil, search_name: false, search_screenname: false, search_nickname: false)
    if user_id.present?
      @users = User.where(id: user_id)
      if @users.present?
        @search_results = @search_results.where(user_id: user_id)
      else
        flash.now[:error] = "The specified author could not be found."
      end
    end

    if template_id.present?
      @templates = Template.where(id: template_id)
      template = @templates.first
      if template.present?
        if @users.present? && template.user_id != @users.first.id
          flash.now[:error] = "The specified author and template do not match; template filter will be ignored."
          @templates = []
        else
          @search_results = @search_results.where(template_id: template_id)
        end
      else
        flash.now[:error] = "The specified template could not be found."
      end
    elsif user_id.present?
      @templates = Template.where(user_id: user_id).ordered.limit(25)
    end

    if name.present?
      where_calc = []
      where_calc << "name LIKE ?" if search_name.present?
      where_calc << "screenname LIKE ?" if search_screenname.present?
      where_calc << "template_name LIKE ?" if search_nickname.present?

      @search_results = @search_results.where(where_calc.join(' OR '), *(['%' + name.to_s + '%'] * where_calc.length))
    end

    @search_results = @search_results.ordered.paginate(page: page, per_page: 25)
  end
end
