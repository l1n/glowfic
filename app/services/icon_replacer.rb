class IconReplacer < Replacer
  def initialize(icon)
    @icon = icon
  end

  def setup(user:, no_icon_url:)
    all_icons = if @icon.has_gallery?
      @icon.galleries.flat_map(&:icons).uniq.compact - [@icon]
    else
      user.galleryless_icons - [@icon]
    end
    @alts = all_icons.sort_by{|i| i.keyword.downcase }

    @gallery = Hash[all_icons.map { |i| [i.id, {url: i.url, keyword: i.keyword}] }]
    @gallery[''] = {url: no_icon_url, keyword: 'No Icon'}

    post_ids = Reply.where(icon_id: @icon.id).select(:post_id).distinct.pluck(:post_id)
    all_posts = Post.where(icon_id: @icon.id) + Post.where(id: post_ids)
    @posts = all_posts.uniq
  end

  def replace(user:, params:)
    unless params[:icon_dropdown].blank? || (new_icon = Icon.find_by_id(params[:icon_dropdown]))
      raise ApiError, "Icon could not be found."
    end

    raise ApiError, "That is not your icon." if new_icon && new_icon.user_id != user.id

    wheres = {icon_id: @icon.id}
    wheres[:post_id] = params[:post_ids] if params[:post_ids].present?
    UpdateModelJob.perform_later(Reply.to_s, wheres, {icon_id: new_icon.try(:id)})
    wheres[:id] = wheres.delete(:post_id) if params[:post_ids].present?
    UpdateModelJob.perform_later(Post.to_s, wheres, {icon_id: new_icon.try(:id)})
  end
end
