class Character::Creater < Character::Cu
  def initialize(user:, params:)
    super(character: Character.new(user: user), user: user, params: params)
  end
end
