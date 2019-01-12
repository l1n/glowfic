class CharacterReplacer < Replacer
  attr_reader :alt_dropdown, :success_msg

  def initialize(character)
    @character = character
  end

  def setup(noicon_url)
    if @character.template
      @alts = @character.template.characters
    else
      @alts = @character.user.characters.where(template_id: nil)
    end
    @alts -= [@character] unless @alts.size <= 1 || @character.aliases.exists?

    icons = @alts.map do |alt|
      if alt.default_icon.present?
        [alt.id, {url: alt.default_icon.url, keyword: alt.default_icon.keyword, aliases: alt.aliases.as_json}]
      else
        [alt.id, {url: view_context.image_path('icons/no-icon.png'), keyword: 'No Icon', aliases: alt.aliases.as_json}]
      end
    end
    @gallery = Hash[icons]
    @gallery[''] = {url: view_context.image_path('icons/no-icon.png'), keyword: 'No Character'}

    @alt_dropdown = @alts.map do |alt|
      name = alt.name
      name += ' | ' + alt.screenname if alt.screenname
      name += ' | ' + alt.template_name if alt.template_name
      name += ' | ' + alt.settings.pluck(:name).join(' & ') if alt.settings.present?
      [name, alt.id]
    end
    @alt = @alts.first

    all_posts = Post.where(character_id: @character.id) + Post.where(id: Reply.where(character_id: @character.id).select(:character_id).distinct.pluck(:post_id))
    @posts = all_posts.uniq
  end

  def replace(params:, user:)
    unless params[:icon_dropdown].blank? || (new_char = Character.find_by_id(params[:icon_dropdown]))
      flash[:error] = "Character could not be found."
      redirect_to replace_character_path(@character) and return
    end

    if new_char && new_char.user_id != current_user.id
      flash[:error] = "That is not your character."
      redirect_to replace_character_path(@character) and return
    end

    orig_alias = nil
    if params[:orig_alias].present? && params[:orig_alias] != 'all'
      orig_alias = CharacterAlias.find_by_id(params[:orig_alias])
      unless orig_alias && orig_alias.character_id == @character.id
        flash[:error] = "Invalid old alias."
        redirect_to replace_character_path(@character) and return
      end
    end

    new_alias_id = nil
    if params[:alias_dropdown].present?
      new_alias = CharacterAlias.find_by_id(params[:alias_dropdown])
      unless new_alias && new_alias.character_id == new_char.try(:id)
        flash[:error] = "Invalid new alias."
        redirect_to replace_character_path(@character) and return
      end
      new_alias_id = new_alias.id
    end

    success_msg = ''
    wheres = {character_id: @character.id}
    updates = {character_id: new_char.try(:id), character_alias_id: new_alias_id}

    if params[:post_ids].present?
      wheres[:post_id] = params[:post_ids]
      success_msg = " in the specified " + 'post'.pluralize(params[:post_ids].size)
    end

    if @character.aliases.exists? && params[:orig_alias] != 'all'
      wheres[:character_alias_id] = orig_alias.try(:id)
    end

    UpdateModelJob.perform_later(Reply.to_s, wheres, updates)
    wheres[:id] = wheres.delete(:post_id) if params[:post_ids].present?
    UpdateModelJob.perform_later(Post.to_s, wheres, updates)
  end
end
