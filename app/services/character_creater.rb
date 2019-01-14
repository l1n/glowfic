class CharacterCreater < CharacterCu
  def initialize(user:, params:)
    super(character: Character.new(user: user), user: user, params: params)
  end
end
