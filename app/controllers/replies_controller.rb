# frozen_string_literal: true
require 'will_paginate/array'

class RepliesController < WritableController
  before_action :login_required, except: [:search, :show, :history]
  before_action :find_reply, only: [:show, :history, :edit, :update, :destroy]
  before_action :editor_setup, only: [:edit]
  before_action :require_permission, only: [:edit, :update]

  def search
    @page_title = 'Search Replies'
    use_javascript('posts/search')

    @post = Post.find_by_id(params[:post_id]) if params[:post_id].present?
    @icon = Icon.find_by_id(params[:icon_id]) if params[:icon_id].present?
    if @post.try(:visible_to?, current_user)
      @users = @post.authors
      char_ids = @post.replies.select(:character_id).distinct.pluck(:character_id) + [@post.character_id]
      @characters = Character.where(id: char_ids).ordered
      @templates = Template.where(id: @characters.map(&:template_id).uniq.compact).ordered
      gon.post_id = @post.id
    else
      @users = User.where(id: params[:author_id]) if params[:author_id].present?
      @characters = Character.where(id: params[:character_id]) if params[:character_id].present?
      @templates = Template.ordered.limit(25)
      @boards = Board.where(id: params[:board_id]) if params[:board_id].present?
      if @post
        # post exists but post not visible
        flash.now[:error] = "You do not have permission to view this post."
        return
      end
    end

    return unless params[:commit].present?

    searcher = ReplySearcher.new(Reply.unscoped)
    @search_results = searcher.search(user_id: params[:author_id], character_id: params[:character_id], icon_id: params[:icon_id], board_id: params[:board_id], content: params[:subj_content], sort: params[:sort], post: @post, template_id: params[:template_id], condensed: params[:condensed])
  end

  def create
    if params[:button_draft]
      draft = make_draft
      redirect_to posts_path and return unless draft.post
      redirect_to post_path(draft.post, page: :unread, anchor: :unread) and return
    elsif params[:button_preview]
      draft = make_draft
      preview(ReplyDraft.reply_from_draft(draft)) and return
    end

    reply = Reply.new(reply_params)
    reply.user = current_user

    if reply.post.present?
      last_seen_reply_order = reply.post.last_seen_reply_for(current_user).try(:reply_order)
      @unseen_replies = reply.post.replies.ordered.paginate(page: 1, per_page: 10)
      @unseen_replies = @unseen_replies.where('reply_order > ?', last_seen_reply_order) if last_seen_reply_order.present?
      most_recent_unseen_reply = @unseen_replies.last
      if most_recent_unseen_reply.present?
        reply.post.mark_read(current_user, reply.post.read_time_for(@unseen_replies))
        num = @unseen_replies.count
        pluraled = num > 1 ? "have been #{num} new replies" : "has been 1 new reply"
        flash.now[:error] = "There #{pluraled} since you last viewed this post."
        draft = make_draft
        preview(ReplyDraft.reply_from_draft(draft)) and return
      end

      if reply.user_id.present? && params[:allow_dupe].blank?
        last_by_user = reply.post.replies.where(user_id: reply.user_id).ordered.last
        if last_by_user.present?
          match_attrs = ['content', 'icon_id', 'character_id', 'character_alias_id']
          if last_by_user.attributes.slice(*match_attrs) == reply.attributes.slice(*match_attrs)
            flash.now[:error] = "This looks like a duplicate. Did you attempt to post this twice? Please resubmit if this was intentional."
            @allow_dupe = true
            draft = make_draft(false)
            preview(ReplyDraft.reply_from_draft(draft)) and return
          end
        end
      end
    end

    if reply.save
      flash[:success] = "Posted!"
      redirect_to reply_path(reply, anchor: "reply-#{reply.id}")
    else
      flash[:error] = {}
      flash[:error][:message] = "Your reply could not be saved because of the following problems:"
      flash[:error][:array] = reply.errors.full_messages
      redirect_to posts_path and return unless reply.post
      redirect_to post_path(reply.post)
    end
  end

  def show
    @page_title = @post.subject
    params[:page] ||= @reply.post_page(per_page)

    show_post(params[:page])
  end

  def history
  end

  def edit
  end

  def update
    @reply.assign_attributes(reply_params)
    preview(@reply) and return if params[:button_preview]

    if current_user.id != @reply.user_id && @reply.audit_comment.blank?
      flash[:error] = "You must provide a reason for your moderator edit."
      editor_setup
      render :edit and return
    end

    @reply.audit_comment = nil if @reply.changes.empty? # don't save an audit for a note and no changes
    unless @reply.save
      flash[:error] = {}
      flash[:error][:message] = "Your reply could not be saved because of the following problems:"
      flash[:error][:array] = @reply.errors.full_messages
      editor_setup
      render :edit and return
    end

    flash[:success] = "Post updated"
    redirect_to reply_path(@reply, anchor: "reply-#{@reply.id}")
  end

  def destroy
    unless @reply.deletable_by?(current_user)
      flash[:error] = "You do not have permission to modify this post."
      redirect_to post_path(@reply.post) and return
    end

    previous_reply = @reply.send(:previous_reply)
    to_page = previous_reply.try(:post_page, per_page) || 1

    # to destroy subsequent replies, do @reply.destroy_subsequent_replies
    begin
      @reply.destroy!
      flash[:success] = "Reply deleted."
      redirect_to post_path(@reply.post, page: to_page)
    rescue ActiveRecord::RecordNotDestroyed
      flash[:error] = {}
      flash[:error][:message] = "Reply could not be deleted."
      flash[:error][:array] = @reply.errors.full_messages
      redirect_to reply_path(@reply, anchor: "reply-#{@reply.id}")
    end
  end

  private

  def find_reply
    @reply = Reply.find_by_id(params[:id])

    unless @reply
      flash[:error] = "Post could not be found."
      redirect_to boards_path and return
    end

    @post = @reply.post
    unless @post.visible_to?(current_user)
      flash[:error] = "You do not have permission to view this post."
      redirect_to boards_path and return
    end

    @page_title = @post.subject
  end

  def require_permission
    unless @reply.editable_by?(current_user)
      flash[:error] = "You do not have permission to modify this post."
      redirect_to post_path(@reply.post)
    end
  end

  def preview(written)
    @written = written
    @post = @written.post
    @written.user = current_user unless @written.user

    @page_title = @post.subject

    editor_setup
    render :preview
  end

  def reply_params
    params.fetch(:reply, {}).permit(
      :post_id,
      :content,
      :character_id,
      :icon_id,
      :audit_comment,
      :character_alias_id,
    )
  end

  def make_draft(show_message=true)
    if (draft = ReplyDraft.draft_for(params[:reply][:post_id], current_user.id))
      draft.assign_attributes(reply_params)
    else
      draft = ReplyDraft.new(reply_params)
      draft.user = current_user
    end

    if draft.save
      flash[:success] = "Draft saved!" if show_message
    else
      flash[:error] = {}
      flash[:error][:message] = "Your draft could not be saved because of the following problems:"
      flash[:error][:array] = draft.errors.full_messages
    end
    draft
  end
end
