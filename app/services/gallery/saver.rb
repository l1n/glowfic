class Gallery::Saver < Generic::Saver
  include Taggable

  attr_reader :gallery

  def initialize(gallery=nil, user:, params:)
    super
    @gallery_groups = process_tags(GalleryGroup, :gallery, :gallery_group_ids)
  end

  private

  def permitted_params
    @params.fetch(:gallery, {}).permit(
      :name,
      galleries_icons_attributes: [
        :id,
        :_destroy,
        icon_attributes: [:url, :keyword, :credit, :id, :_destroy, :s3_key]
      ],
      icon_ids: [],
      ungrouped_gallery_ids: [],
    )
  end
end
