class CharacterUpdater < CharacterCu
  def initialize(character:, user:, params:)
    @character = character
    super
  end

  def perform
    @character.assign_attributes(@params)
    build_template

    # TODO once assign_attributes doesn't save, use @character.audit_comment and uncomment clearing
    if current_user.id != @character.user_id && params.fetch(:character, {})[:audit_comment].blank?
      raise ApiError, "You must provide a reason for your moderator edit."
    end
    # @character.audit_comment = nil if @character.changes.empty?

    params = @params
    
    Character.transaction do
      @character.settings = process_tags(Setting, :character, :setting_ids)
      @character.gallery_groups = process_tags(GalleryGroup, :character, :gallery_group_ids)
      @character.save!
    end
  end
end
