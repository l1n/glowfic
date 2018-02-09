class SplitPostTextIntoReplies < ActiveRecord::Migration[5.1]
  def up
    Post.each do |post|
      post.replies.each do |reply|
        reply.reply_order = reply.reply_order + 1
      end
      reply.create!(
        post_id: post.id,
        reply_order: 0,
        user_id: post.user_id,
        character_id: post.character_id,
        character_alias_id: post.character_alias_id,
        icon_id: post.icon_id,
        content: post.content,
        created_at: post.created_at,
        updated_at: post.updated_at
      )
    end
    change_table :posts do |t|
      t.remove :character_id, :character_alias_id, :icon_id, :content
    end
  end

  def down
    change_table :posts do |t|
      t.integer :character_id
      t.integer :character_alias_id
      t.integer :icon_id
      t.text :content
    end
    Post.each do |post|
      reply = reply.find_by(reply_order: 0)
      if post.user_id == reply.user_id
        post.character_id = reply.character_id
        post.character_alias_id = reply.character_alias_id
        post.icon_id = reply.icon_id
        post.content = reply.content
      else
        raise "Post user does not match inital reply's user"
      end
    end
  end
end
