class IconMultiRemover < Object
  attr_reader :success_msg, :gallery

  def initialize(params)
    @from_gallery = params[:gallery_delete]
    @gallery = Gallery.find_by_id(params[:gallery_id])
    icon_ids = (params[:marked_ids] || []).map(&:to_i).reject(&:zero?)
    if icon_ids.empty? || (@icons = Icon.where(id: icon_ids)).empty?
      flash[:error] = "No icons selected."
      redirect_to user_galleries_path(current_user) and return
    end
  end

  def perform(user)
    if @from_gallery
      remove(user)
    else
      delete(user)
    end
  end

  def remove(user)
    unless @gallery
      flash[:error] = "Gallery could not be found."
      redirect_to user_galleries_path(current_user) and return
    end

    unless @gallery.user_id == current_user.id
      flash[:error] = "That is not your gallery."
      redirect_to user_galleries_path(current_user) and return
    end

    @icons.each do |icon|
      next unless icon.user_id == current_user.id
      @gallery.icons.destroy(icon)
    end

    flash[:success] = "Icons removed from gallery."
    icon_redirect(@gallery) and return
  end

  def delete(user)
    @icons.each do |icon|
      next unless icon.user_id == user.id
      icon.destroy
    end
    flash[:success] = "Icons deleted."
  end
end
