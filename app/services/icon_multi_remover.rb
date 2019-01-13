class IconMultiRemover < Object
  attr_reader :success_msg, :gallery

  def initialize(params)
    @from_gallery = params[:gallery_delete]
    @gallery = Gallery.find_by(id: params[:gallery_id])
    icon_ids = (params[:marked_ids] || []).map(&:to_i).reject(&:zero?)
    raise ApiError, "No icons selected." if icon_ids.empty? || (@icons = Icon.where(id: icon_ids)).empty?
  end

  def perform(user)
    if @from_gallery
      remove(user)
    else
      delete(user)
    end
  end

  def remove(user)
    raise ApiError, "Gallery could not be found." unless @gallery
    raise ApiError, "That is not your gallery." unless @gallery.user_id == user.id

    @icons.each do |icon|
      next unless icon.user_id == user.id
      @gallery.icons.destroy(icon)
    end

    @success_msg = "Icons removed from gallery."
  end

  def delete(user)
    @icons.each do |icon|
      next unless icon.user_id == user.id
      icon.destroy!
    end
    @success_msg = "Icons deleted."
  end
end
