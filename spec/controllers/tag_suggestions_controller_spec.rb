RSpec.describe TagSuggestionsController do
  render_views

  let(:author) { create(:user) }
  let(:reader) { create(:user) }
  let(:post_record) { create(:post, user: author) }
  let(:tag) { create(:label) }

  describe "GET new" do
    it "requires login" do
      get :new, params: { post_id: post_record.id }
      expect(response).to redirect_to(root_url)
    end

    it "refuses readonly users" do
      login_as(create(:reader_user))
      get :new, params: { post_id: post_record.id }
      expect(response).to redirect_to(continuities_path)
    end

    it "handles a missing post" do
      login_as(reader)
      get :new, params: { post_id: -1 }
      expect(flash[:error]).to eq("Post could not be found.")
    end

    it "succeeds" do
      login_as(reader)
      get :new, params: { post_id: post_record.id }
      expect(response).to have_http_status(200)
    end
  end

  describe "POST create" do
    it "creates a suggestion" do
      login_as(reader)
      expect {
        post :create, params: { post_id: post_record.id, tag_suggestion: { tag_id: tag.id } }
      }.to change { TagSuggestion.count }.by(1)
      expect(flash[:success]).to eq("Thanks — your suggestion has been sent to the author.")
    end

    it "reports a tag the suggester can already see" do
      PostTag.create!(post: post_record, tag: tag)
      login_as(reader)
      post :create, params: { post_id: post_record.id, tag_suggestion: { tag_id: tag.id } }
      expect(flash[:error]).to eq("That tag is already on this post.")
    end

    it "gives the same confirmation for a silently deduped suggestion" do
      TagSuggestion.create!(post: post_record, user: create(:user), tag: tag, status: :rejected)
      login_as(reader)

      expect {
        post :create, params: { post_id: post_record.id, tag_suggestion: { tag_id: tag.id } }
      }.not_to change { TagSuggestion.count }
      expect(flash[:success]).to eq("Thanks — your suggestion has been sent to the author.")
      expect(flash[:error]).to be_nil
    end

    it "re-renders on invalid input" do
      post_record.update!(allow_tag_suggestions: false)
      login_as(reader)
      post :create, params: { post_id: post_record.id, tag_suggestion: { tag_id: tag.id } }
      expect(response).to render_template(:new)
    end
  end

  describe "GET index" do
    it "shows only the current user's posts' suggestions" do
      mine = TagSuggestion.create!(post: post_record, user: reader, tag: tag)
      TagSuggestion.create!(post: create(:post), user: reader, tag: create(:label))
      login_as(author)

      get :index
      expect(assigns(:pending)).to eq([mine])
    end

    it "lists resolved suggestions with an allow-again action for rejections" do
      rejected = TagSuggestion.create!(post: post_record, user: reader, tag: tag)
      rejected.reject!(resolver: author)
      accepted = TagSuggestion.create!(post: post_record, user: reader, tag: create(:label))
      accepted.accept!(resolver: author)
      login_as(author)

      get :index

      expect(assigns(:resolved)).to match_array([rejected, accepted])
      expect(response.body).to include("Allow again")
    end

    it "separates endorsements from pending decisions" do
      create_list(:reply, 2, post: post_record, user: author)
      PostTag.create!(post: post_record, tag: tag, spoiler: true)
      TagSuggestion.submit(post: post_record, user: reader, tag: tag)
      login_as(author)

      get :index
      expect(assigns(:endorsements).length).to eq(1)
      expect(assigns(:pending)).to be_empty
    end
  end

  describe "resolution" do
    let!(:suggestion) { TagSuggestion.create!(post: post_record, user: reader, tag: tag) }

    it "refuses a user who is not the author" do
      login_as(reader)
      post :accept, params: { id: suggestion.id }
      expect(flash[:error]).to eq("You do not have permission to do that.")
      expect(suggestion.reload).to be_pending
    end

    it "accepts" do
      login_as(author)
      post :accept, params: { id: suggestion.id }
      expect(post_record.reload.labels).to eq([tag])
    end

    it "rejects" do
      login_as(author)
      post :reject, params: { id: suggestion.id }
      expect(suggestion.reload).to be_rejected
    end

    it "allows a rejected tag to be suggested again" do
      suggestion.reject!(resolver: author)
      login_as(author)
      delete :allow_again, params: { id: suggestion.id }
      expect(TagSuggestion.find_by(id: suggestion.id)).to be_nil
    end

    it "handles a missing suggestion" do
      login_as(author)
      post :accept, params: { id: -1 }
      expect(flash[:error]).to eq("Suggestion could not be found.")
    end
  end
end
