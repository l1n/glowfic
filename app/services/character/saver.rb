class Character::Saver < Object
  include Taggable

  attr_reader :character

  def initialize(character: nil, user:, params:)
    character ||= Character.new(user: user)
    @character = character
    @user = user
    @params = params
    @settings = process_tags(Setting, :character, :setting_ids)
    @gallery_groups = process_tags(GalleryGroup, :character, :gallery_group_ids)
  end

  def perform_create
    perform
  end

  def perform_update
    build
    # TODO once assign_attributes doesn't save, use @character.audit_comment and uncomment clearing
    raise NoModNoteError if @user.id != @character.user_id && @params.fetch(:character, {})[:audit_comment].blank?
    # @character.audit_comment = nil if @character.changes.empty?
    save!
  end

  def perform
    build
    save!
  end

  private

  def build
    @character.assign_attributes(character_params)
    build_template
  end

  def save!
    Character.transaction do
      @character.settings = @settings
      @character.gallery_groups = @gallery_groups
      @character.save!
    end
  end

  def build_template
    return unless @params[:new_template].present?
    return unless @character.user == @user
    @character.build_template unless @character.template
    @character.template.user = @user
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
    if @character.user == @user
      permitted.last[:template_attributes] = [:name, :id]
      permitted.insert(0, :default_icon_id)
    end
    @params.fetch(:character, {}).permit(permitted)
  end
end
