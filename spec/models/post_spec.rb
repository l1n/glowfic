require "spec_helper"

RSpec.describe Post do
  it "should have the right timestamps" do
    # creation
    post = create(:post)
    expect(post.edited_at).to eq(post.created_at)
    expect(post.tagged_at).to eq(post.created_at)

    # edited with no replies
    post.content = 'new content'
    post.save
    expect(post.tagged_at).to eq(post.edited_at)
    expect(post.tagged_at).to be > post.created_at
    old_edited_at = post.edited_at

    # reply created
    reply = create(:reply, post: post)
    post.reload
    expect(post.tagged_at).to eq(reply.created_at)
    expect(post.edited_at).to eq(old_edited_at)
    expect(post.tagged_at).to be > post.edited_at
    old_tagged_at = post.tagged_at

    # edited with replies
    post.content = 'newer content'
    post.save
    expect(post.tagged_at).to eq(old_tagged_at)
    expect(post.edited_at).to be > old_edited_at

    # second reply created
    reply2 = create(:reply, post: post)
    post.reload
    expect(post.tagged_at).to eq(reply2.created_at)
    expect(post.updated_at).to be >= reply2.created_at
    expect(post.tagged_at).to be > post.edited_at
    old_tagged_at = post.tagged_at
    old_edited_at = post.edited_at

    # first reply updated
    reply.content = 'new content'
    reply.skip_post_update = true unless reply.post.last_reply_id == reply.id
    reply.save
    post.reload
    expect(post.tagged_at).to eq(old_tagged_at) # BAD
    expect(post.edited_at).to eq(old_edited_at)

    # second reply updated
    reply2.content = 'new content'
    reply2.skip_post_update = true unless reply2.post.last_reply_id == reply2.id
    reply2.save
    post.reload
    expect(post.tagged_at).to eq(reply2.updated_at)
    expect(post.edited_at).to eq(old_edited_at)
  end

  it "should allow blank content" do
    post = create(:post, content: nil)
    expect(post.id).not_to be_nil
  end

  describe "#destroy" do
    it "should delete views" do
      post = create(:post)
      user = create(:user)
      expect(PostView.count).to be_zero
      post.mark_read(user)
      expect(PostView.count).not_to be_zero
      post.destroy
      expect(PostView.count).to be_zero
    end
  end

  describe "#edited_at" do
    it "should update when a field is changed" do
      post = create(:post)
      expect(post.edited_at).to eq(post.created_at)
      post.content = 'new content now'
      post.save
      expect(post.edited_at).not_to eq(post.created_at)
    end

    it "should update when multiple fields are changed" do
      post = create(:post)
      expect(post.edited_at).to eq(post.created_at)
      post.content = 'new content now'
      post.description = 'description'
      post.save
      expect(post.edited_at).not_to eq(post.created_at)
    end

    it "should not update when skip is set" do
      post = create(:post)
      expect(post.edited_at).to eq(post.created_at)
      post.skip_edited = true
      post.touch
      expect(post.edited_at).to eq(post.created_at)
    end

    it "should not update when a reply is made" do
      post = create(:post)
      expect(post.edited_at).to eq(post.created_at)
      create(:reply, post: post, user: post.user)
      expect(post.edited_at).to eq(post.created_at)
    end
  end

  describe "#section_order" do
    it "should be set on create" do
      board = create(:board)
      5.times do |i|
        post = create(:post, board: board)
        expect(post.section_order).to eq(i)
      end
    end

    it "should be set in its section on create" do
      board = create(:board)
      section = create(:board_section, board: board)
      5.times do |i|
        post = create(:post, board: board, section_id: section.id)
        expect(post.section_order).to eq(i)
      end
    end

    it "should handle mix and match section/no section creates" do
      board = create(:board)
      section = create(:board_section, board: board)
      expect(section.section_order).to eq(0)
      5.times do |i|
        post = create(:post, board: board, section_id: section.id)
        expect(post.section_order).to eq(i)
      end
      post = create(:post, board: board)
      expect(post.section_order).to eq(1)
      post = create(:post, board: board)
      expect(post.section_order).to eq(2)
      post = create(:post, board: board, section_id: section.id)
      expect(post.section_order).to eq(5)
      section = create(:board_section, board: board)
      expect(section.section_order).to eq(3)
      post = create(:post, board: board)
      expect(post.section_order).to eq(4)
    end

    it "should update when section is changed" do
      board = create(:board)
      section = create(:board_section, board: board)
      post = create(:post, board: board, section_id: section.id)
      expect(post.section_order).to eq(0)
      post = create(:post, board: board, section_id: section.id)
      expect(post.section_order).to eq(1)
      section = create(:board_section, board: board)
      post.section_id = section.id
      post.save
      post.reload
      expect(post.section_order).to eq(0)
    end

    it "should not increment on non-section update" do
      board = create(:board)
      post = create(:post, board: board)
      expect(post.section_order).to eq(0)
      create(:post, board: board)
      create(:post, board: board)
      post.update_attributes(content: 'new content')
      post.reload
      expect(post.section_order).to eq(0)
    end
  end
end
