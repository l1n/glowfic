class CharacterCu < Object
  include Taggable

  attr_reader :character

  def initialize(user:, params:)
    @user = user
    @params = character_params(params)
  end

  def perform
  end

  private

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

  def build_template
    return unless @params[:new_template].present?
    return unless @character.user == @user
    @character.build_template unless @character.template
    @character.template.user = @user
  end
end
