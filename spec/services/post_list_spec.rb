require "spec_helper"

RSpec.describe PostList do
  describe "#visible_to" do
    it "logged out only shows public posts" do
      create(:post, privacy: Concealable::PRIVATE)
      create_list(:post, 2, privacy: Concealable::ACCESS_LIST)
      create_list(:post, 2, privacy: Concealable::REGISTERED)
      posts = create_list(:post, 3, privacy: Concealable::PUBLIC)
      list = PostList.new(Post.all)
      expect(list.send(:visible_to, {user: nil})).to match_array(posts)
    end

    describe "logged in" do
      let(:user) { create(:user) }

      it "shows constellation-only posts" do
        posts = create_list(:post, 2, privacy: Concealable::REGISTERED)
        list = PostList.new(Post.all)
        expect(list.send(:visible_to, {user: user})).to match_array(posts)
      end

      it "shows own access-listed posts" do
        posts = create_list(:post, 2, privacy: Concealable::ACCESS_LIST, user_id: user.id)
        list = PostList.new(Post.all)
        expect(list.send(:visible_to, {user: user})).to match_array(posts)
      end

      it "shows access-listed posts with access" do
        post = create(:post, privacy: Concealable::ACCESS_LIST)
        PostViewer.create!(post: post, user: user)
        list = PostList.new(Post.all)
        expect(list.send(:visible_to, {user: user})).to eq([post])
      end

      it "does not show other access-listed posts" do
        create_list(:post, 2, privacy: Concealable::ACCESS_LIST)
        list = PostList.new(Post.all)
        expect(list.send(:visible_to, {user: user})).to be_empty
      end

      it "shows own private posts" do
        posts = create_list(:post, 2, privacy: Concealable::PRIVATE, user_id: user.id)
        list = PostList.new(Post.all)
        expect(list.send(:visible_to, {user: user})).to match_array(posts)
      end

      it "does not show other private posts" do
        create_list(:post, 2, privacy: Concealable::PRIVATE)
        list = PostList.new(Post.all)
        expect(list.send(:visible_to, {user: user})).to be_empty
      end
    end
  end
end
