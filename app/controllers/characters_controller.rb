# frozen_string_literal: true
class CharactersController < ApplicationController
  include Taggable

  before_action :login_required, except: [:index, :show, :facecasts, :search]
  before_action :find_character, only: [:show, :edit, :update, :duplicate, :destroy, :replace, :do_replace]
  before_action :find_group, only: :index
  before_action :require_own_character, only: [:edit, :update, :duplicate, :replace, :do_replace]
  before_action :build_editor, only: [:new, :edit]

  def index
    (return if login_required) unless params[:user_id].present?

    @user = User.find_by_id(params[:user_id]) || current_user
    unless @user
      flash[:error] = "User could not be found."
      redirect_to users_path and return
    end

    @page_title = if @user.id == current_user.try(:id)
      "Your Characters"
    else
      @user.username + "'s Characters"
    end
  end

  def new
    @page_title = 'New Character'
    @character = Character.new(template_id: params[:template_id], user: current_user)
    @character.build_template(user: current_user) unless @character.template
  end

  def create
    @character = Character.new(user: current_user)
    @character.assign_attributes(character_params)
    @character.settings = process_tags(Setting, :character, :setting_ids)
    @character.gallery_groups = process_tags(GalleryGroup, :character, :gallery_group_ids)
    build_template

    if @character.save
      flash[:success] = "Character saved successfully."
      redirect_to character_path(@character) and return
    end

    @page_title = "New Character"
    flash.now[:error] = {}
    flash.now[:error][:message] = "Your character could not be saved."
    flash.now[:error][:array] = @character.errors.full_messages
    build_editor
    render :new
  end

  def show
    @page_title = @character.name
    @posts = posts_from_relation(@character.recent_posts)
    use_javascript('characters/show') if @character.user_id == current_user.try(:id)
  end

  def edit
    @page_title = 'Edit Character: ' + @character.name
  end

  def update
    @character.assign_attributes(character_params)
    build_template

    # TODO once assign_attributes doesn't save, use @character.audit_comment and uncomment clearing
    if current_user.id != @character.user_id && params.fetch(:character, {})[:audit_comment].blank?
      flash[:error] = "You must provide a reason for your moderator edit."
      build_editor
      render :edit and return
    end
    # @character.audit_comment = nil if @character.changes.empty?

    begin
      Character.transaction do
        @character.settings = process_tags(Setting, :character, :setting_ids)
        @character.gallery_groups = process_tags(GalleryGroup, :character, :gallery_group_ids)
        @character.save!
      end
      flash[:success] = "Character saved successfully."
      redirect_to character_path(@character)
    rescue ActiveRecord::RecordInvalid
      @page_title = "Edit Character: " + @character.name
      flash.now[:error] = {}
      flash.now[:error][:message] = "Your character could not be saved."
      flash.now[:error][:array] = @character.errors.full_messages
      build_editor
      render :edit
    end
  end

  def duplicate
    dupe = @character.dup

    Character.transaction do
      dupe.gallery_groups = @character.gallery_groups
      dupe.settings = @character.settings
      dupe.ungrouped_gallery_ids = @character.ungrouped_gallery_ids
      @character.aliases.find_each do |calias|
        dupalias = calias.dup
        dupe.aliases << dupalias
        dupalias.save!
      end
      dupe.save!
    end

    flash[:success] = "Character duplicated successfully. You are now editing the new character."
    redirect_to edit_character_path(dupe)
  end

  def destroy
    unless @character.deletable_by?(current_user)
      flash[:error] = "You do not have permission to edit that character."
      redirect_to user_characters_path(current_user) and return
    end

    begin
      @character.destroy!
      flash[:success] = "Character deleted successfully."
      redirect_to user_characters_path(current_user)
    rescue ActiveRecord::RecordNotDestroyed
      flash[:error] = {}
      flash[:error][:message] = "Character could not be deleted."
      flash[:error][:array] = @character.errors.full_messages
      redirect_to character_path(@character)
    end
  end

  def facecasts
    @page_title = 'Facecasts'
    chars = Character.where('pb is not null')
      .joins(:user)
      .left_outer_joins(:template)
      .pluck('characters.id, characters.name, characters.pb, users.id, users.username, templates.id, templates.name')
    @pbs = []

    pb_struct = Struct.new(:item_id, :item_name, :type, :pb, :user_id, :username)
    chars.each do |dataset|
      id, name, pb, user_id, username, template_id, template_name = dataset
      if template_id.present?
        item_id, item_name, type = template_id, template_name, Template
      else
        item_id, item_name, type = id, name, Character
      end
      @pbs << pb_struct.new(item_id, item_name, type, pb, user_id, username)
    end
    @pbs.uniq!

    if params[:sort] == "name"
      @pbs.sort_by! {|x| [x[:item_name].downcase, x[:pb].downcase, x[:username].downcase]}
    elsif params[:sort] == "writer"
      @pbs.sort_by! {|x| [x[:username].downcase, x[:pb].downcase, x[:item_name].downcase]}
    else
      @pbs.sort_by! {|x| [x[:pb].downcase, x[:username].downcase, x[:item_name].downcase]}
    end
  end

  def replace
    @page_title = 'Replace Character: ' + @character.name
    replacer = CharacterReplacer.new(@character)
    replacer.setup(view_context.image_path('icons/no-icon.png'))

    @alts = replacer.alts
    use_javascript('icons')

    gon.gallery = replacer.gallery

    @alt_dropdown = replacer.alt_dropdown
    @alt = @alts.first

    @posts = replacer.posts
  end

  def do_replace
    replacer = CharacterReplacer.new(@character)
    begin
      replacer.replace(params: params, user: current_user)
    rescue ApiError => e
      flash[:error] = e.message
      redirect_to replace_character_path(@character) and return
    else
      flash[:success] = "All uses of this character#{replacer.success_msg} will be replaced."
      redirect_to character_path(@character)
    end
  end

  def search
    @page_title = 'Search Characters'
    use_javascript('posts/search')
    @users = []
    @templates = []
    return unless params[:commit].present?

    @search_results = Character.unscoped

    if params[:author_id].present?
      @users = User.where(id: params[:author_id])
      if @users.present?
        @search_results = @search_results.where(user_id: params[:author_id])
      else
        flash.now[:error] = "The specified author could not be found."
      end
    end

    if params[:template_id].present?
      @templates = Template.where(id: params[:template_id])
      template = @templates.first
      if template.present?
        if @users.present? && template.user_id != @users.first.id
          flash.now[:error] = "The specified author and template do not match; template filter will be ignored."
          @templates = []
        else
          @search_results = @search_results.where(template_id: params[:template_id])
        end
      else
        flash.now[:error] = "The specified template could not be found."
      end
    elsif params[:author_id].present?
      @templates = Template.where(user_id: params[:author_id]).ordered.limit(25)
    end

    if params[:name].present?
      where_calc = []
      where_calc << "name LIKE ?" if params[:search_name].present?
      where_calc << "screenname LIKE ?" if params[:search_screenname].present?
      where_calc << "template_name LIKE ?" if params[:search_nickname].present?

      @search_results = @search_results.where(where_calc.join(' OR '), *(['%' + params[:name].to_s + '%'] * where_calc.length))
    end

    @search_results = @search_results.ordered.paginate(page: page, per_page: 25)
  end

  private

  def find_character
    unless (@character = Character.find_by_id(params[:id]))
      flash[:error] = "Character could not be found."
      if logged_in?
        redirect_to user_characters_path(current_user)
      else
        redirect_to root_path
      end
    end
  end

  def find_group
    return unless params[:group_id].present?
    @group = CharacterGroup.find_by_id(params[:group_id])
  end

  def require_own_character
    unless @character.editable_by?(current_user)
      flash[:error] = "You do not have permission to edit that character."
      redirect_to user_characters_path(current_user) and return
    end
  end

  def build_editor
    faked = Struct.new(:name, :id)
    user = @character.try(:user) || current_user
    @templates = user.templates.ordered
    new_group = faked.new('— Create New Group —', 0)
    @groups = user.character_groups.order('name asc') + [new_group]
    use_javascript('characters/editor')
    gon.character_id = @character.try(:id) || ''
    if @character.present? && @character.template.nil? && @character.user == current_user
      @character.build_template(user: user)
    end
    gon.user_id = user.id
    @aliases = @character.aliases.ordered if @character
    gon.mod_editing = (user != current_user)
    groups = @character.try(:gallery_groups) || []
    gon.gallery_groups = groups.map {|group| group.as_json(include: [:gallery_ids], user_id: user.id) }
  end

  def build_template
    return unless params[:new_template].present?
    return unless @character.user == current_user
    @character.build_template unless @character.template
    @character.template.user = current_user
  end

  def character_params
    permitted = [
      :name,
      :template_name,
      :screenname,
      :template_id,
      :pb,
      :description,
      :audit_comment,
      ungrouped_gallery_ids: [],
    ]
    if @character.user == current_user
      permitted.last[:template_attributes] = [:name, :id]
      permitted.insert(0, :default_icon_id)
    end
    params.fetch(:character, {}).permit(permitted)
  end

  # logic replicated from page_view
  def character_split
    return @character_split if @character_split
    if logged_in?
      @character_split = params[:character_split] || current_user.default_character_split
    else
      @character_split = session[:character_split] = params[:character_split] || session[:character_split] || 'template'
    end
  end
  helper_method :character_split
end
