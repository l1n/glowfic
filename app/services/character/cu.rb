class Character::Cu < Object
  include Taggable

  attr_reader :character

  def initialize(character:, user:, params:)
    @character = character
    @user = user
    @params = params
    @settings = process_tags(Setting, :character, :setting_ids)
    @gallery_groups = process_tags(GalleryGroup, :character, :gallery_group_ids)
  end

  def perform
    build
    save!
  end

  private

  def build
    @character.assign_attributes(character_params(@params))
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

  def character_params(params)
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
    params.fetch(:character, {}).permit(permitted)
  end
end
