# frozen_string_literal: true
class IndexesController < CrudController
  def index
    super
    @indexes = Index.order('id asc').paginate(per_page: 25, page: page)
  end

  def show
    super
    @sectionless = @index.posts.where(index_posts: {index_section_id: nil})
    @sectionless = @sectionless.ordered_by_index
    @sectionless = posts_from_relation(@sectionless, with_pagination: false, select: ', index_posts.description as index_description')
    @sectionless = @sectionless.select { |p| p.visible_to?(current_user) }
  end

  def edit
    @page_title = "Edit Index: #{@index.name}"
  end

  def update
    unless @index.update(index_params)
      flash.now[:error] = {}
      flash.now[:error][:message] = "Index could not be saved because of the following problems:"
      flash.now[:error][:array] = @index.errors.full_messages
      @page_title = "Edit Index: #{@index.name}"
      render action: :edit and return
    end

    flash[:success] = "Index saved!"
    redirect_to index_path(@index)
  end

  def destroy
    @index.destroy!
    flash[:success] = "Index deleted."
    redirect_to indexes_path
  rescue ActiveRecord::RecordNotDestroyed
    flash[:error] = {}
    flash[:error][:message] = "Index could not be deleted."
    flash[:error][:array] = @index.errors.full_messages
    redirect_to index_path(@index)
  end

  private

  def permitted_params
    params.fetch(:index, {}).permit(:name, :description, :privacy, :open_to_anyone)
  end

  def before_create
    @model.user = current_user
  end
end
