class CharacterCreater < CharacterCu
  def initialize(user:, params:)
    @character = Character.new(user: user)
    super
  end

  def perform
    params = @params
    @character.assign_attributes(@params)
    @character.settings = process_tags(Setting, :character, :setting_ids)
    @character.gallery_groups = process_tags(GalleryGroup, :character, :gallery_group_ids)
    build_template

    @character.save!
  end
end
