class IconReplacer < Replacer
  def initialize(icon)
    @icon = icon
  end

  def replace(user:, params:)
    new_icon = check_target(dropdown: params[:icon_dropdown], user: user)

    wheres = {icon_id: @icon.id}
    wheres[:post_id] = params[:post_ids] if params[:post_ids].present?
    updates = {icon_id: new_icon.try(:id)}
    replace_jobs(wheres: wheres, updates: updates, post_ids: params[:post_ids])
  end

  private

  def find_alts
    if @icon.has_gallery?
      all_icons = @icon.galleries.flat_map(&:icons).uniq.compact
    else
      all_icons = @icon.user.galleryless_icons
    end
    all_icons -= [@icon]
    all_icons.sort_by{|i| i.keyword.downcase }
  end

  def find_posts
    post_ids = Reply.where(icon_id: @icon.id).select(:post_id).distinct.pluck(:post_id)
    (Post.where(icon_id: @icon.id) + Post.where(id: post_ids)).uniq
  end

  def construct_gallery(no_icon_url)
    gallery = Hash[@alts.map { |i| [i.id, {url: i.url, keyword: i.keyword}] }]
    gallery[''] = {url: no_icon_url, keyword: 'No Icon'}
    gallery
  end

  def check_target(dropdown:, user:)
    unless dropdown.blank? || (new_icon = Icon.find_by(id: dropdown))
      raise ApiError, "Icon could not be found."
    end

    raise ApiError, "That is not your icon." if new_icon && new_icon.user_id != user.id

    new_icon
  end
end
