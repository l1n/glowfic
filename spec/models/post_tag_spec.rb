RSpec.describe PostTag do
  let(:author) { create(:user) }
  let(:post) { create(:post, user: author) }
  let(:tag) { create(:label) }

  def read_to(user, reply)
    post.mark_read(user, at_time: reply.created_at)
  end

  describe "#revealed_to?" do
    it "reveals a non-spoiler tagging to anyone, including logged out" do
      tagging = PostTag.create!(post: post, tag: tag)
      expect(tagging.revealed_to?(nil)).to eq(true)
      expect(tagging.revealed_to?(create(:user))).to eq(true)
    end

    it "hides a spoiler tagging from a logged out viewer" do
      tagging = PostTag.create!(post: post, tag: tag, spoiler: true)
      expect(tagging.revealed_to?(nil)).to eq(false)
    end

    it "always reveals to the post author" do
      tagging = PostTag.create!(post: post, tag: tag, spoiler: true, reveal_after_reply_order: 99)
      expect(tagging.revealed_to?(author)).to eq(true)
    end

    it "hides from a reader who has not reached the threshold" do
      replies = create_list(:reply, 3, post: post, user: author)
      tagging = PostTag.create!(post: post, tag: tag, spoiler: true, reveal_after_reply_order: 2)
      reader = create(:user)
      read_to(reader, replies.first)

      expect(tagging.revealed_to?(reader)).to eq(false)
    end

    it "reveals to a reader who has passed the threshold" do
      replies = create_list(:reply, 3, post: post, user: author)
      tagging = PostTag.create!(post: post, tag: tag, spoiler: true, reveal_after_reply_order: 1)
      reader = create(:user)
      read_to(reader, replies.last)

      expect(tagging.revealed_to?(reader)).to eq(true)
    end

    it "hides from a reader who has never opened the post" do
      create_list(:reply, 2, post: post, user: author)
      tagging = PostTag.create!(post: post, tag: tag, spoiler: true)
      expect(tagging.revealed_to?(create(:user))).to eq(false)
    end

    it "with no threshold reveals only at the end of the post" do
      replies = create_list(:reply, 3, post: post, user: author)
      tagging = PostTag.create!(post: post, tag: tag, spoiler: true)
      reader = create(:user)

      read_to(reader, replies.first)
      expect(tagging.revealed_to?(reader)).to eq(false)

      read_to(reader, replies.last)
      expect(tagging.reload.revealed_to?(reader)).to eq(true)
    end
  end

  describe "validations" do
    it "rejects a reveal threshold without the spoiler flag" do
      tagging = PostTag.new(post: post, tag: tag, spoiler: false, reveal_after_reply_order: 3)
      expect(tagging).not_to be_valid
    end

    it "rejects a negative reveal threshold" do
      tagging = PostTag.new(post: post, tag: tag, spoiler: true, reveal_after_reply_order: -1)
      expect(tagging).not_to be_valid
    end
  end

  describe "post-level helpers" do
    it "splits visible tags by type and counts what stays hidden" do
      replies = create_list(:reply, 3, post: post, user: author)
      label = create(:label)
      setting = create(:setting)
      warning = create(:content_warning)
      PostTag.create!(post: post, tag: label)
      PostTag.create!(post: post, tag: setting, spoiler: true, reveal_after_reply_order: 3)
      PostTag.create!(post: post, tag: warning)

      reader = create(:user)
      read_to(reader, replies.first)

      expect(post.visible_tags_for(reader, Label)).to eq([label])
      expect(post.visible_tags_for(reader, ContentWarning)).to eq([warning])
      expect(post.visible_tags_for(reader, Setting)).to be_empty
      expect(post.hidden_spoiler_tag_count_for(reader)).to eq(1)
    end

    it "shows the author everything with nothing hidden" do
      PostTag.create!(post: post, tag: tag, spoiler: true)
      expect(post.visible_tags_for(author, Label)).to eq([tag])
      expect(post.hidden_spoiler_tag_count_for(author)).to eq(0)
    end
  end

  describe "reverse lookup" do
    it "excludes spoilered taggings" do
      visible = PostTag.create!(post: post, tag: tag)
      other_post = create(:post)
      PostTag.create!(post: other_post, tag: tag, spoiler: true)

      expect(PostTag.for_reverse_lookup.where(tag_id: tag.id)).to eq([visible])
    end

    it "omits a spoilered post from the tag's post listing" do
      listed = create(:post)
      PostTag.create!(post: listed, tag: tag)
      hidden = create(:post)
      PostTag.create!(post: hidden, tag: tag, spoiler: true)

      expect(tag.posts).to include(hidden)
      expect(tag.unspoilered_posts).to eq([listed])
    end

    it "omits spoilered content warnings from post listings" do
      warning = create(:content_warning)
      PostTag.create!(post: post, tag: warning, spoiler: true)

      expect(post.content_warnings).to eq([warning])
      expect(post.unspoilered_content_warnings).to be_empty
      expect(post.has_content_warnings?).to eq(false)
    end
  end
end
