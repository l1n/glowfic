class CharacterUpdater < CharacterCu
  def perform
    build
    # TODO once assign_attributes doesn't save, use @character.audit_comment and uncomment clearing
    if current_user.id != @character.user_id && params.fetch(:character, {})[:audit_comment].blank?
      raise ApiError, "You must provide a reason for your moderator edit."
    end
    # @character.audit_comment = nil if @character.changes.empty?
    save
  end
end
