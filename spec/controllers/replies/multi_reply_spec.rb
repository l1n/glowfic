RSpec.describe RepliesController, 'multi reply editing' do
  # Regression coverage for the "Here Ends This Thread" marker vanishing after
  # replies are appended through the multi-reply editor. The appended replies
  # set skip_post_update, so the post's cached last_reply must be advanced
  # explicitly once they land at the end of the thread.
  def submit_multi_reply(edited_reply, *new_contents)
    json = [{ id: edited_reply.id, content: edited_reply.content }]
    json += new_contents.map { |content| { content: content } }
    post :create, params: {
      button_submit_previewed_multi_reply: true,
      multi_replies_json: json.to_json,
    }
  end

  it "advances the post's last reply when appending to the end of the thread" do
    user = create(:user)
    reply_post = create(:post, user: user)
    last = create(:reply, post: reply_post, user: user)
    expect(reply_post.reload.last_reply).to eq(last)

    login_as(user)
    submit_multi_reply(last, 'appended reply')

    reply_post.reload
    expect(reply_post.replies.count).to eq(2)
    appended = reply_post.replies.ordered.last
    expect(appended.content).to eq('appended reply')
    expect(reply_post.last_reply).to eq(appended)
    expect(reply_post.last_user_id).to eq(user.id)
  end

  it "advances the last reply when appending multiple replies" do
    user = create(:user)
    reply_post = create(:post, user: user)
    last = create(:reply, post: reply_post, user: user)

    login_as(user)
    submit_multi_reply(last, 'appended one', 'appended two')

    reply_post.reload
    expect(reply_post.replies.count).to eq(3)
    appended = reply_post.replies.ordered.last
    expect(appended.content).to eq('appended two')
    expect(reply_post.last_reply).to eq(appended)
  end

  it "leaves the last reply untouched when inserting into the middle of the thread" do
    user = create(:user)
    reply_post = create(:post, user: user)
    middle = create(:reply, post: reply_post, user: user)
    last = create(:reply, post: reply_post, user: user)
    expect(reply_post.reload.last_reply).to eq(last)

    login_as(user)
    submit_multi_reply(middle, 'inserted reply')

    reply_post.reload
    expect(reply_post.replies.count).to eq(3)
    expect(reply_post.last_reply).to eq(last)
  end
end
