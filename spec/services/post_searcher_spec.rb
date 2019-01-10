require "spec_helper"

RSpec.describe PostSearcher do
  it "finds all when no arguments given" do
    4.times do create(:post) end
    get :search, params: { commit: true }
    expect(assigns(:search_results)).to match_array(Post.all)
  end

  it "filters by continuity" do
    post = create(:post)
    post2 = create(:post, board: post.board)
    create(:post)
    get :search, params: { commit: true, board_id: post.board_id }
    expect(assigns(:search_results)).to match_array([post, post2])
  end

  it "filters by setting" do
    setting = create(:setting)
    post = create(:post)
    post.settings << setting
    create(:post)
    get :search, params: { commit: true, setting_id: setting.id }
    expect(assigns(:search_results)).to match_array([post])
  end

  it "filters by subject" do
    post1 = create(:post, subject: 'contains stars')
    post2 = create(:post, subject: 'contains Stars cased')
    create(:post, subject: 'unrelated')
    get :search, params: { commit: true, subject: 'stars' }
    expect(assigns(:search_results)).to match_array([post1, post2])
  end

  it "does not mix up subject with content" do
    create(:post, subject: 'unrelated', content: 'contains stars')
    get :search, params: { commit: true, subject: 'stars' }
    expect(assigns(:search_results)).to be_empty
  end

  it "filters by exact match subject" do
    skip "TODO not yet implemented"
  end

  it "filters by authors" do
    posts = Array.new(4) { create(:post) }
    filtered_post = posts.last
    first_post = posts.first
    create(:reply, post: first_post, user: filtered_post.user)
    get :search, params: { commit: true, author_id: [filtered_post.user_id] }
    expect(assigns(:search_results)).to match_array([filtered_post, first_post])
  end

  it "filters by multiple authors" do
    author1 = create(:user)
    author2 = create(:user)
    nonauthor = create(:user)

    found_posts = []
    create(:post, user: author1) # one author but not the other, post
    post = create(:post, user: nonauthor) # one author but not the other, reply
    create(:reply, user: author2, post: post)

    post = create(:post, user: author1) # both authors, one post only
    create(:reply, post: post, user: author2)
    found_posts << post

    post = create(:post, user: nonauthor) # both authors, replies only
    create(:reply, post: post, user: author1)
    create(:reply, post: post, user: author2)
    found_posts << post

    get :search, params: { commit: true, author_id: [author1.id, author2.id] }
    expect(assigns(:search_results)).to match_array(found_posts)
  end

  it "filters by characters" do
    create(:reply, with_character: true)
    reply = create(:reply, with_character: true)
    post = create(:post, character: reply.character, user: reply.user)
    get :search, params: { commit: true, character_id: reply.character_id }
    expect(assigns(:search_results)).to match_array([reply.post, post])
  end

  it "filters by completed" do
    create(:post)
    post = create(:post, status: Post::STATUS_COMPLETE)
    get :search, params: { commit: true, completed: true }
    expect(assigns(:search_results)).to match_array(post)
  end

  it "sorts posts by tagged_at" do
    posts = Array.new(4) do create(:post) end
    create(:reply, post: posts[2])
    create(:reply, post: posts[1])
    get :search, params: { commit: true }
    expect(assigns(:search_results)).to eq([posts[1], posts[2], posts[3], posts[0]])
  end
end
