class Generic::Saver < Object
  def initialize(user:, params:, model:)
    @user = user
    @params = params
    @model = model
  end

  def perform
    build
    save!
  end

  alias_method :perform_create, :perform
  alias_method :perform_update, :perform

  private

  def build
    @model.assign_attributes(permitted_params)
  end

  def save!
    ApplicationRecord.transaction do
      @model.settings = @settings unless @settings.nil?
      @model.gallery_groups = @gallery_groups unless @gallery_groups.nil?
      @model.save!
    end
  end
end
